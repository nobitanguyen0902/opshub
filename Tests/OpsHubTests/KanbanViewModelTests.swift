import XCTest
@testable import OpsHub

@MainActor
final class KanbanViewModelTests: XCTestCase {
    func testRefreshMergesLogicalWorkflowsAndExternalHermesTasks() async {
        var workflow = makeTriageWorkflow()
        workflow.title = "OpsHub workflow"
        let request = HermesTaskCreateRequest(
            title: "External task", body: "", assignee: "developer",
            workspacePath: "/tmp/external", priority: 1, idempotencyKey: "external"
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [.fixture(id: "t_external", request: request)]),
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards.map(\.title), ["OpsHub workflow", "External task"])
        XCTAssertTrue(model.snapshot?.cards.first?.isWorkflowOwned == true)
        XCTAssertFalse(model.snapshot?.cards.last?.isWorkflowOwned == true)
    }

    func testRefreshFailureKeepsPreviousSnapshot() async {
        let hermes = ViewModelHermesStub(
            taskResults: [.success([]), .failure(.incompatibleJSON(command: "list"))]
        )
        let model = KanbanViewModel(
            hermes: hermes,
            coordinator: ViewModelCoordinatorStub(workflows: [])
        )
        await model.refresh()
        let previous = model.snapshot
        await model.refresh()
        XCTAssertEqual(model.snapshot, previous)
        XCTAssertNotNil(model.errorMessage)
    }

    func testRefreshHidesHermesStageTasksOwnedByAWorkflow() async {
        var workflow = makeTriageWorkflow()
        workflow.phase = .active
        workflow.currentStage = .architect
        workflow.stageReferences = [
            .init(
                stage: .architect,
                attempt: 0,
                hermesTaskID: "t_internal",
                idempotencyKey: "opshub:workflow:architect:0",
                createdAt: Date(timeIntervalSince1970: 1)
            )
        ]
        let internalTask = HermesKanbanTask.fixture(
            id: "t_internal",
            request: .init(title: "Internal stage", body: "", assignee: "architect", workspacePath: "/tmp/repo", priority: 1, idempotencyKey: "internal")
        )
        let externalTask = HermesKanbanTask.fixture(
            id: "t_external",
            request: .init(title: "External", body: "", assignee: "developer", workspacePath: "/tmp/external", priority: 1, idempotencyKey: "external")
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [internalTask, externalTask]),
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards.map(\.displayID), [workflow.id.uuidString, "t_external"])
    }

    func testExternalTaskHasNoWorkflowActionsButLoadsDetailAndLog() async {
        let task = HermesKanbanTask.fixture(
            id: "t_external",
            request: .init(title: "External", body: "", assignee: "developer", workspacePath: "/tmp/external", priority: 1, idempotencyKey: "external")
        )
        let hermes = ViewModelHermesStub(tasks: [task])
        await hermes.setDetail(.fixture(task: task))
        await hermes.setLog("external log", for: task.id)
        let model = KanbanViewModel(hermes: hermes, coordinator: ViewModelCoordinatorStub(workflows: []))

        await model.refresh()
        model.selectedCardID = .hermes(task.id)
        await model.startSelected()
        await model.approveSelected()
        await model.cancelSelected()
        await model.retrySelected()
        await model.loadSelectedDetail()
        await model.loadSelectedLog()

        XCTAssertEqual(model.snapshot?.cards.first?.availableActions, [])
        XCTAssertEqual(model.selectedHermesDetail?.task.id, task.id)
        XCTAssertEqual(model.selectedLog, "external log")
    }

    func testWorkflowActionsMatchPhase() async {
        let triage = makeTriageWorkflow()
        var approval = makeTriageWorkflow(id: "00000000-0000-0000-0000-000000000002")
        approval.phase = .approvalRequired
        var blocked = makeTriageWorkflow(id: "00000000-0000-0000-0000-000000000003")
        blocked.phase = .blocked

        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: [triage, approval, blocked])
        )
        await model.refresh()

        XCTAssertEqual(actions(for: triage.id, in: model), [.start])
        XCTAssertEqual(actions(for: approval.id, in: model), [.approve, .cancel])
        XCTAssertEqual(actions(for: blocked.id, in: model), [.retry])
    }

    func testDoubleStartInvokesCoordinatorOnce() async {
        let workflow = makeTriageWorkflow()
        let coordinator = ViewModelCoordinatorStub(workflows: [workflow], startDelayNanoseconds: 100_000_000)
        let model = KanbanViewModel(hermes: ViewModelHermesStub(tasks: []), coordinator: coordinator)
        await model.refresh()
        model.selectedCardID = .workflow(workflow.id)

        async let first: Void = model.startSelected()
        async let second: Void = model.startSelected()
        _ = await (first, second)

        let startCalls = await coordinator.startCallCount()
        XCTAssertEqual(startCalls, 1)
    }

    func testLoadingSelectedDetailPreservesSelectedCardID() async {
        let task = HermesKanbanTask.fixture(
            id: "t_external",
            request: .init(title: "External", body: "", assignee: "developer", workspacePath: "/tmp/external", priority: 1, idempotencyKey: "external")
        )
        let hermes = ViewModelHermesStub(tasks: [task])
        await hermes.setDetail(.fixture(task: task))
        let model = KanbanViewModel(hermes: hermes, coordinator: ViewModelCoordinatorStub(workflows: []))
        await model.refresh()
        model.selectedCardID = .hermes(task.id)

        await model.loadSelectedDetail()

        XCTAssertEqual(model.selectedCardID, .hermes(task.id))
    }

    func testAutoRefreshStopsAfterCancellationAndRefreshGuardPreventsOverlap() async {
        let hermes = ViewModelHermesStub(tasks: [], listDelayNanoseconds: 100_000_000)
        let coordinator = ViewModelCoordinatorStub(workflows: [])
        let model = KanbanViewModel(
            hermes: hermes,
            coordinator: coordinator,
            sleeper: { _ in try await Task.sleep(for: .seconds(60)) }
        )

        let poll = Task { await model.autoRefresh() }
        await hermes.waitForListCalls(atLeast: 1)
        async let first: Void = model.refresh()
        async let second: Void = model.refresh()
        _ = await (first, second)
        poll.cancel()
        _ = await poll.value

        let listCallsAfterCancellation = await hermes.listCallCount()
        try? await Task.sleep(for: .milliseconds(50))
        let listCallsAfterWaiting = await hermes.listCallCount()
        XCTAssertEqual(listCallsAfterWaiting, listCallsAfterCancellation)
        XCTAssertLessThanOrEqual(listCallsAfterCancellation, 2)
    }
}

@MainActor
private func actions(for workflowID: UUID, in model: KanbanViewModel) -> Set<KanbanAvailableAction>? {
    model.snapshot?.cards.first(where: { $0.id == .workflow(workflowID) })?.availableActions
}

private actor ViewModelHermesStub: HermesKanbanServicing {
    private var taskResults: [Result<[HermesKanbanTask], KanbanCommandError>]
    private var details: [String: HermesKanbanTaskDetail] = [:]
    private var logs: [String: String] = [:]
    private let listDelayNanoseconds: UInt64
    private(set) var listCalls = 0

    init(tasks: [HermesKanbanTask], listDelayNanoseconds: UInt64 = 0) {
        taskResults = [.success(tasks)]
        self.listDelayNanoseconds = listDelayNanoseconds
    }

    init(taskResults: [Result<[HermesKanbanTask], KanbanCommandError>]) {
        self.taskResults = taskResults
        listDelayNanoseconds = 0
    }

    func listTasks() async throws -> [HermesKanbanTask] {
        listCalls += 1
        if listDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: listDelayNanoseconds) }
        guard !taskResults.isEmpty else { return [] }
        return try taskResults.removeFirst().get()
    }

    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail {
        guard let detail = details[id] else {
            throw KanbanCommandError.failed(command: "show", exitCode: 1, stderr: "missing fixture")
        }
        return detail
    }

    func runs(taskID: String) async throws -> [HermesKanbanRun] { [] }
    func log(taskID: String, tailBytes: Int) async throws -> String { logs[taskID] ?? "" }
    func isAvailable() async -> Bool { true }
    func profileExists(_ profile: String) async -> Bool { true }
    func isGatewayRunning() async -> Bool { true }
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask { .fixture(id: "t_created", request: request) }
    func reclaim(taskID: String, reason: String) async throws {}
    func block(taskID: String, reason: String) async throws {}
    func unblock(taskID: String, reason: String) async throws {}
    func setDetail(_ detail: HermesKanbanTaskDetail) { details[detail.task.id] = detail }
    func setLog(_ value: String, for taskID: String) { logs[taskID] = value }
    func listCallCount() -> Int { listCalls }
    func waitForListCalls(atLeast expected: Int) async {
        while listCalls < expected { await Task.yield() }
    }
}

private actor ViewModelCoordinatorStub: KanbanWorkflowCoordinating {
    private var value: [KanbanWorkflow]
    private let startDelayNanoseconds: UInt64
    private(set) var startCalls = 0

    init(workflows: [KanbanWorkflow], startDelayNanoseconds: UInt64 = 0) {
        value = workflows
        self.startDelayNanoseconds = startDelayNanoseconds
    }

    func workflows() async throws -> [KanbanWorkflow] { value }
    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow { value[0] }
    func start(workflowID: UUID) async throws -> KanbanWorkflow {
        startCalls += 1
        if startDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: startDelayNanoseconds) }
        return value[0]
    }
    func refresh() async throws -> [KanbanWorkflow] { value }
    func approve(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func cancel(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func retry(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func resumePendingTransitions() async throws -> [KanbanWorkflow] { value }
    func startCallCount() -> Int { startCalls }
}

private extension HermesKanbanTask {
    static func fixture(id: String, request: HermesTaskCreateRequest) -> Self {
        .init(
            id: id, title: request.title, body: request.body,
            assignee: request.assignee, status: .ready, priority: request.priority,
            tenant: nil, workspaceKind: "dir", workspacePath: request.workspacePath,
            branchName: nil, projectID: nil, createdBy: "opshub",
            createdAt: 1, startedAt: nil, completedAt: nil, result: nil
        )
    }
}

private extension HermesKanbanTaskDetail {
    static func fixture(task: HermesKanbanTask) -> Self {
        .init(task: task, latestSummary: nil, parents: [], children: [], comments: [], events: [], runs: [])
    }
}

private func makeTriageWorkflow(id: String = "00000000-0000-0000-0000-000000000001") -> KanbanWorkflow {
    .init(
        schemaVersion: 1,
        id: UUID(uuidString: id)!,
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal,
        phase: .triage,
        currentStage: nil,
        repairCount: 0,
        stageReferences: [],
        pendingTransition: nil,
        cancellationReason: nil,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}
