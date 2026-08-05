import XCTest
@testable import OpsHub

@MainActor
final class KanbanViewModelTests: XCTestCase {
    func testCreateDraftSucceedsWhenFollowUpRefreshFails() async {
        let workflow = makeTriageWorkflow()
        let coordinator = ViewModelCoordinatorStub(workflows: [workflow])
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(taskResults: [.failure(.incompatibleJSON(command: "list"))]),
            coordinator: coordinator
        )

        let created = await model.createDraft(
            .init(
                title: "Task",
                objective: "Objective",
                acceptanceCriteria: ["Criterion"],
                workspacePath: "/tmp/repo",
                priority: .normal
            )
        )

        XCTAssertTrue(created)
        let createCalls = await coordinator.createDraftCallCount()
        XCTAssertEqual(createCalls, 1)
        XCTAssertNotNil(model.errorMessage)
    }

    func testWorkspaceValidationFailureStaysLocalToNewTaskSheet() async {
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: []),
            workspaceValidator: ViewModelWorkspaceValidator(error: .notGitRepository)
        )

        do {
            _ = try await model.validateDraftWorkspacePath("/not-a-repository")
            XCTFail("Expected workspace validation to fail")
        } catch {
            XCTAssertEqual(error as? KanbanStartGuardError, .notGitRepository)
        }

        XCTAssertNil(model.errorMessage)
    }

    func testWorkflowStageChangeClearsStaleInspectorDetailBeforeReloading() async {
        let workflowID = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
        let architectWorkflow = activeWorkflow(
            id: workflowID,
            stage: .architect,
            taskID: "t_architect"
        )
        let developerWorkflow = activeWorkflow(
            id: workflowID,
            stage: .developer,
            taskID: "t_developer"
        )
        let coordinator = ViewModelCoordinatorStub(workflows: [architectWorkflow])
        let hermes = DeferredViewModelHermesStub(tasks: [])
        let model = KanbanViewModel(hermes: hermes, coordinator: coordinator)

        await model.refresh()
        model.selectedCardID = .workflow(workflowID)
        XCTAssertEqual(model.selectedHermesTaskID, "t_architect")

        let staleDetail = Task { await model.loadSelectedDetail() }
        await hermes.waitForDetailRequest("t_architect")
        await coordinator.setWorkflows([developerWorkflow])
        await model.refresh()
        await hermes.resolveDetail(
            "t_architect",
            with: .success(.fixture(task: task(id: "t_architect")))
        )
        _ = await staleDetail.value

        XCTAssertEqual(model.selectedHermesTaskID, "t_developer")
        XCTAssertNil(model.selectedHermesDetail)
        XCTAssertNil(model.selectedDetail)
        XCTAssertNil(model.selectedLog)
    }

    func testCreateDraftReportsSuccessForValidatedSheetDismissal() async {
        let workflow = makeTriageWorkflow()
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        let created = await model.createDraft(
            .init(
                title: "Task",
                objective: "Objective",
                acceptanceCriteria: ["Criterion"],
                workspacePath: "/tmp/repo",
                priority: .normal
            )
        )

        XCTAssertTrue(created)
    }

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

    func testRefreshSortsMixedCardsByDescendingPriorityThenCreatedTimeAndID() async {
        var olderManaged = makeTriageWorkflow(
            id: "00000000-0000-0000-0000-000000000002",
            createdAt: Date(timeIntervalSince1970: 10)
        )
        olderManaged.title = "Older managed"
        olderManaged.priority = .high

        var urgentManaged = makeTriageWorkflow(
            id: "00000000-0000-0000-0000-000000000003",
            createdAt: Date(timeIntervalSince1970: 30)
        )
        urgentManaged.title = "Urgent managed"
        urgentManaged.priority = .urgent

        let tiedExternalB = task(
            id: "t_external_b",
            title: "External B",
            status: .triage,
            priority: .high,
            createdAt: 20
        )
        let tiedExternalA = task(
            id: "t_external_a",
            title: "External A",
            status: .triage,
            priority: .high,
            createdAt: 20
        )
        let lowExternal = task(
            id: "t_external_low",
            title: "External low",
            status: .triage,
            priority: .low,
            createdAt: 1
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [lowExternal, tiedExternalB, tiedExternalA]),
            coordinator: ViewModelCoordinatorStub(workflows: [olderManaged, urgentManaged])
        )

        await model.refresh()

        XCTAssertEqual(
            model.snapshot?.cards.map(\.title),
            ["Urgent managed", "Older managed", "External A", "External B", "External low"]
        )
    }

    func testRefreshSortsMissingCreatedAtAfterPopulatedAndUsesStableIDAndKindTies() async {
        let sharedID = "00000000-0000-0000-0000-000000000020"
        var managedTie = makeTriageWorkflow(
            id: sharedID,
            createdAt: Date(timeIntervalSince1970: 20)
        )
        managedTie.title = "Managed kind tie"
        managedTie.priority = .high

        let externalKindTie = task(
            id: sharedID,
            title: "External kind tie",
            status: .triage,
            priority: .high,
            createdAt: 20
        )
        let populatedExternal = task(
            id: "t_populated",
            title: "Populated external",
            status: .triage,
            priority: .high,
            createdAt: 30
        )
        let missingExternalB = task(
            id: "t_missing_b",
            title: "Missing B",
            status: .triage,
            priority: .high,
            createdAt: nil
        )
        let missingExternalA = task(
            id: "t_missing_a",
            title: "Missing A",
            status: .triage,
            priority: .high,
            createdAt: nil
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(
                tasks: [missingExternalB, populatedExternal, externalKindTie, missingExternalA]
            ),
            coordinator: ViewModelCoordinatorStub(workflows: [managedTie])
        )

        await model.refresh()

        XCTAssertEqual(
            model.snapshot?.cards.map(\.title),
            [
                "Managed kind tie",
                "External kind tie",
                "Populated external",
                "Missing A",
                "Missing B",
            ]
        )
    }

    func testTriageDraftExposesLogicalContentWithoutCallingHermesDetailOrLog() async {
        let workflow = makeTriageWorkflow()
        let hermes = ViewModelHermesStub(tasks: [])
        let model = KanbanViewModel(
            hermes: hermes,
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        await model.refresh()
        model.selectedCardID = .workflow(workflow.id)
        await model.loadSelectedDetail()
        await model.loadSelectedLog()

        XCTAssertNil(model.selectedHermesTaskID)
        XCTAssertEqual(model.selectedLogicalWorkflow?.objective, "Objective")
        XCTAssertEqual(model.selectedLogicalWorkflow?.acceptanceCriteria, ["Criterion"])
        XCTAssertNil(model.selectedHermesDetail)
        XCTAssertNil(model.selectedLog)
        let detailCalls = await hermes.detailCallCount()
        let logCalls = await hermes.logCallCount()
        XCTAssertEqual(detailCalls, 0)
        XCTAssertEqual(logCalls, 0)
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

    func testRefreshHidesBlockedAndNeedsAttentionWorkflowsWhenAllReferencedTasksAreMissing() async {
        var blocked = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
            stage: .architect,
            taskID: "t_missing_blocked"
        )
        blocked.phase = .blocked
        var needsAttention = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
            stage: .developer,
            taskID: "t_missing_attention"
        )
        needsAttention.phase = .needsAttention
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: [blocked, needsAttention])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards, [])
    }

    func testRefreshKeepsDraftWithNoReferencesWhenHermesListIsEmpty() async {
        let draft = makeTriageWorkflow()
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: [draft])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards.map(\.id), [.workflow(draft.id)])
        XCTAssertEqual(model.snapshot?.cards.first?.column, .triage)
    }

    func testRefreshHidesNeedsAttentionWorkflowWhenStageCreationNeverProducedATask() async {
        var workflow = makeTriageWorkflow(
            id: "00000000-0000-0000-0000-000000000024"
        )
        workflow.phase = .needsAttention
        workflow.currentStage = .architect
        workflow.pendingTransition = pendingTransition(kind: .createStage)

        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: []),
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards, [])
    }

    func testRefreshHidesWorkflowWhenCurrentTaskIsMissingEvenIfPreviousTaskExists() async {
        var workflow = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
            stage: .developer,
            taskID: "t_missing_current"
        )
        workflow.stageReferences.insert(
            .init(
                stage: .architect,
                attempt: 0,
                hermesTaskID: "t_existing_previous",
                idempotencyKey: "opshub:workflow:architect:0",
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            at: 0
        )
        let existingTask = task(id: "t_existing_previous")
        let unrelatedTask = task(id: "t_external")
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [existingTask, unrelatedTask]),
            coordinator: ViewModelCoordinatorStub(workflows: [workflow])
        )

        await model.refresh()

        XCTAssertEqual(model.snapshot?.cards.map(\.id), [.hermes(unrelatedTask.id)])
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
        var approval = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            stage: .architect,
            taskID: "t_approval"
        )
        approval.phase = .approvalRequired
        var blocked = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            stage: .architect,
            taskID: "t_blocked"
        )
        blocked.phase = .blocked

        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [task(id: "t_approval"), task(id: "t_blocked")]),
            coordinator: ViewModelCoordinatorStub(workflows: [triage, approval, blocked])
        )
        await model.refresh()

        XCTAssertEqual(actions(for: triage.id, in: model), [.start])
        XCTAssertEqual(actions(for: approval.id, in: model), [.approve, .cancel])
        XCTAssertEqual(actions(for: blocked.id, in: model), [.retry])
    }

    func testCancellationRecoveryActionIsScopedToManagedNeedsAttentionCancelTransition() async {
        let recoverable = cancellationRecoveryWorkflow(
            id: "00000000-0000-0000-0000-000000000010"
        )
        var genericAttention = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
            stage: .architect,
            taskID: "t_generic_attention"
        )
        genericAttention.phase = .needsAttention
        var unrelatedAttention = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
            stage: .architect,
            taskID: "t_unrelated_attention"
        )
        unrelatedAttention.phase = .needsAttention
        unrelatedAttention.pendingTransition = pendingTransition(kind: .createStage)
        var otherPhase = activeWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000015")!,
            stage: .architect,
            taskID: "t_other_phase"
        )
        otherPhase.phase = .blocked
        otherPhase.pendingTransition = pendingTransition(kind: .cancel)
        let externalTask = HermesKanbanTask.fixture(
            id: "t_external_recovery",
            request: .init(
                title: "External",
                body: "",
                assignee: "developer",
                workspacePath: "/tmp/external",
                priority: 1,
                idempotencyKey: "external-recovery"
            )
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [
                task(id: representativeTaskID(for: recoverable)),
                task(id: "t_generic_attention"),
                task(id: "t_unrelated_attention"),
                task(id: "t_other_phase"),
                externalTask,
            ]),
            coordinator: ViewModelCoordinatorStub(
                workflows: [recoverable, genericAttention, unrelatedAttention, otherPhase]
            )
        )

        await model.refresh()

        XCTAssertEqual(actions(for: recoverable.id, in: model), [.retryCancellationRecovery])
        XCTAssertEqual(actions(for: genericAttention.id, in: model), [])
        XCTAssertEqual(actions(for: unrelatedAttention.id, in: model), [])
        XCTAssertEqual(actions(for: otherPhase.id, in: model), [])
        XCTAssertEqual(
            model.snapshot?.cards.first(where: { $0.id == .hermes(externalTask.id) })?.availableActions,
            []
        )
    }

    func testDoubleCancellationRecoveryInvokesCoordinatorOnce() async {
        let workflow = cancellationRecoveryWorkflow(
            id: "00000000-0000-0000-0000-000000000013"
        )
        let coordinator = ViewModelCoordinatorStub(
            workflows: [workflow],
            recoveryDelayNanoseconds: 100_000_000
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [task(id: representativeTaskID(for: workflow))]),
            coordinator: coordinator
        )
        await model.refresh()
        model.selectedCardID = .workflow(workflow.id)

        async let first: Void = model.retryCancellationRecoverySelected()
        async let second: Void = model.retryCancellationRecoverySelected()
        _ = await (first, second)

        let calls = await coordinator.recoveryCallCount()
        XCTAssertEqual(calls, 1)
    }

    func testCancellationRecoveryErrorRemainsVisible() async {
        let workflow = cancellationRecoveryWorkflow(
            id: "00000000-0000-0000-0000-000000000014"
        )
        let coordinator = ViewModelCoordinatorStub(
            workflows: [workflow],
            recoveryFails: true
        )
        let model = KanbanViewModel(
            hermes: ViewModelHermesStub(tasks: [task(id: representativeTaskID(for: workflow))]),
            coordinator: coordinator
        )
        await model.refresh()
        model.selectedCardID = .workflow(workflow.id)

        await model.retryCancellationRecoverySelected()

        XCTAssertNotNil(model.errorMessage)
        let calls = await coordinator.recoveryCallCount()
        XCTAssertEqual(calls, 1)
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

    func testSelectionSwapDropsStaleDetailAndLogResponses() async {
        let (first, second) = externalTasks()
        let hermes = DeferredViewModelHermesStub(tasks: [first, second])
        let model = KanbanViewModel(hermes: hermes, coordinator: ViewModelCoordinatorStub(workflows: []))
        await model.refresh()

        model.selectedCardID = .hermes(first.id)
        let staleDetail = Task { await model.loadSelectedDetail() }
        await hermes.waitForDetailRequest(first.id)
        model.selectedCardID = .hermes(second.id)
        let currentDetail = Task { await model.loadSelectedDetail() }
        await hermes.waitForDetailRequest(second.id)
        await hermes.resolveDetail(second.id, with: .success(.fixture(task: second)))
        _ = await currentDetail.value
        await hermes.resolveDetail(first.id, with: .failure(.incompatibleJSON(command: "show")))
        _ = await staleDetail.value

        XCTAssertEqual(model.selectedHermesDetail?.task.id, second.id)
        XCTAssertNil(model.errorMessage)

        model.selectedCardID = .hermes(first.id)
        let staleLog = Task { await model.loadSelectedLog() }
        await hermes.waitForLogRequest(first.id)
        model.selectedCardID = .hermes(second.id)
        let currentLog = Task { await model.loadSelectedLog() }
        await hermes.waitForLogRequest(second.id)
        await hermes.resolveLog(second.id, with: .success("current log"))
        _ = await currentLog.value
        await hermes.resolveLog(first.id, with: .failure(.incompatibleJSON(command: "log")))
        _ = await staleLog.value

        XCTAssertEqual(model.selectedLog, "current log")
        XCTAssertNil(model.errorMessage)
    }

    func testCancelledDetailAndLogRequestsDoNotPublishAfterCompletion() async {
        let (first, _) = externalTasks()
        let hermes = DeferredViewModelHermesStub(tasks: [first])
        let model = KanbanViewModel(hermes: hermes, coordinator: ViewModelCoordinatorStub(workflows: []))
        await model.refresh()
        model.selectedCardID = .hermes(first.id)

        let detail = Task { await model.loadSelectedDetail() }
        await hermes.waitForDetailRequest(first.id)
        detail.cancel()
        await hermes.resolveDetail(first.id, with: .success(.fixture(task: first)))
        _ = await detail.value

        XCTAssertNil(model.selectedHermesDetail)
        XCTAssertNil(model.errorMessage)

        let log = Task { await model.loadSelectedLog() }
        await hermes.waitForLogRequest(first.id)
        log.cancel()
        await hermes.resolveLog(first.id, with: .failure(.incompatibleJSON(command: "log")))
        _ = await log.value

        XCTAssertNil(model.selectedLog)
        XCTAssertNil(model.errorMessage)
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

private func externalTasks() -> (HermesKanbanTask, HermesKanbanTask) {
    let first = HermesKanbanTask.fixture(
        id: "t_first",
        request: .init(title: "First", body: "", assignee: "developer", workspacePath: "/tmp/first", priority: 1, idempotencyKey: "first")
    )
    let second = HermesKanbanTask.fixture(
        id: "t_second",
        request: .init(title: "Second", body: "", assignee: "developer", workspacePath: "/tmp/second", priority: 1, idempotencyKey: "second")
    )
    return (first, second)
}

private actor ViewModelHermesStub: HermesKanbanServicing {
    private var taskResults: [Result<[HermesKanbanTask], KanbanCommandError>]
    private var details: [String: HermesKanbanTaskDetail] = [:]
    private var logs: [String: String] = [:]
    private let listDelayNanoseconds: UInt64
    private(set) var listCalls = 0
    private(set) var detailCalls = 0
    private(set) var logCalls = 0

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
        detailCalls += 1
        guard let detail = details[id] else {
            throw KanbanCommandError.failed(command: "show", exitCode: 1, stderr: "missing fixture")
        }
        return detail
    }

    func runs(taskID: String) async throws -> [HermesKanbanRun] { [] }
    func log(taskID: String, tailBytes: Int) async throws -> String {
        logCalls += 1
        return logs[taskID] ?? ""
    }
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
    func detailCallCount() -> Int { detailCalls }
    func logCallCount() -> Int { logCalls }
    func waitForListCalls(atLeast expected: Int) async {
        while listCalls < expected { await Task.yield() }
    }
}

private actor DeferredViewModelHermesStub: HermesKanbanServicing {
    private var tasks: [HermesKanbanTask]
    private var detailRequests: [String: [CheckedContinuation<Result<HermesKanbanTaskDetail, KanbanCommandError>, Never>]] = [:]
    private var logRequests: [String: [CheckedContinuation<Result<String, KanbanCommandError>, Never>]] = [:]

    init(tasks: [HermesKanbanTask]) {
        self.tasks = tasks
    }

    func listTasks() async throws -> [HermesKanbanTask] { tasks }

    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail {
        let result = await withCheckedContinuation { continuation in
            detailRequests[id, default: []].append(continuation)
        }
        return try result.get()
    }

    func runs(taskID: String) async throws -> [HermesKanbanRun] { [] }

    func log(taskID: String, tailBytes: Int) async throws -> String {
        let result = await withCheckedContinuation { continuation in
            logRequests[taskID, default: []].append(continuation)
        }
        return try result.get()
    }

    func isAvailable() async -> Bool { true }
    func profileExists(_ profile: String) async -> Bool { true }
    func isGatewayRunning() async -> Bool { true }
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask { tasks[0] }
    func reclaim(taskID: String, reason: String) async throws {}
    func block(taskID: String, reason: String) async throws {}
    func unblock(taskID: String, reason: String) async throws {}

    func waitForDetailRequest(_ taskID: String) async {
        while detailRequests[taskID]?.isEmpty ?? true { await Task.yield() }
    }

    func waitForLogRequest(_ taskID: String) async {
        while logRequests[taskID]?.isEmpty ?? true { await Task.yield() }
    }

    func resolveDetail(_ taskID: String, with result: Result<HermesKanbanTaskDetail, KanbanCommandError>) {
        guard var requests = detailRequests[taskID], !requests.isEmpty else { return }
        let continuation = requests.removeFirst()
        detailRequests[taskID] = requests
        continuation.resume(returning: result)
    }

    func resolveLog(_ taskID: String, with result: Result<String, KanbanCommandError>) {
        guard var requests = logRequests[taskID], !requests.isEmpty else { return }
        let continuation = requests.removeFirst()
        logRequests[taskID] = requests
        continuation.resume(returning: result)
    }
}

private actor ViewModelCoordinatorStub: KanbanWorkflowCoordinating {
    private var value: [KanbanWorkflow]
    private let startDelayNanoseconds: UInt64
    private let recoveryDelayNanoseconds: UInt64
    private let recoveryFails: Bool
    private(set) var startCalls = 0
    private(set) var createDraftCalls = 0
    private(set) var recoveryCalls = 0

    init(
        workflows: [KanbanWorkflow],
        startDelayNanoseconds: UInt64 = 0,
        recoveryDelayNanoseconds: UInt64 = 0,
        recoveryFails: Bool = false
    ) {
        value = workflows
        self.startDelayNanoseconds = startDelayNanoseconds
        self.recoveryDelayNanoseconds = recoveryDelayNanoseconds
        self.recoveryFails = recoveryFails
    }

    func workflows() async throws -> [KanbanWorkflow] { value }
    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow {
        createDraftCalls += 1
        return value[0]
    }
    func start(workflowID: UUID) async throws -> KanbanWorkflow {
        startCalls += 1
        if startDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: startDelayNanoseconds) }
        return value[0]
    }
    func refresh() async throws -> [KanbanWorkflow] { value }
    func approve(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func cancel(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func recoverCancellation(workflowID: UUID) async throws -> KanbanWorkflow {
        recoveryCalls += 1
        if recoveryDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: recoveryDelayNanoseconds)
        }
        if recoveryFails { throw KanbanWorkflowError.unsafeRecovery }
        return value[0]
    }
    func retry(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func resumePendingTransitions() async throws -> [KanbanWorkflow] { value }
    func startCallCount() -> Int { startCalls }
    func createDraftCallCount() -> Int { createDraftCalls }
    func recoveryCallCount() -> Int { recoveryCalls }
    func setWorkflows(_ workflows: [KanbanWorkflow]) { value = workflows }
}

private struct ViewModelWorkspaceValidator: KanbanWorkspaceValidating {
    let error: KanbanStartGuardError

    func validateDraftPath(_ url: URL) async throws -> URL { throw error }
    func validateStart(_ url: URL) async throws -> URL { throw error }
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

private func makeTriageWorkflow(
    id: String = "00000000-0000-0000-0000-000000000001",
    createdAt: Date = Date(timeIntervalSince1970: 1)
) -> KanbanWorkflow {
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
        createdAt: createdAt,
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}

private func cancellationRecoveryWorkflow(id: String) -> KanbanWorkflow {
    var workflow = activeWorkflow(
        id: UUID(uuidString: id)!,
        stage: .architect,
        taskID: "t_cancel_\(id)"
    )
    workflow.phase = .needsAttention
    workflow.pendingTransition = pendingTransition(kind: .cancel)
    workflow.attentionReason = "Cancellation recovery requires confirmation."
    return workflow
}

private func representativeTaskID(for workflow: KanbanWorkflow) -> String {
    workflow.stageReferences.last!.hermesTaskID
}

private func pendingTransition(kind: KanbanPendingTransition.Kind) -> KanbanPendingTransition {
    .init(
        kind: kind,
        stage: kind == .createStage ? .developer : nil,
        attempt: kind == .createStage ? 0 : nil,
        idempotencyKey: "pending-\(kind.rawValue)",
        previousPhase: .active,
        cancelReclaimAttempted: kind == .cancel ? false : nil,
        cancelReclaimed: kind == .cancel ? false : nil,
        cancelPreReclaimStatus: kind == .cancel ? .running : nil,
        startedAt: Date(timeIntervalSince1970: 1)
    )
}

private func activeWorkflow(id: UUID, stage: KanbanStage, taskID: String) -> KanbanWorkflow {
    var workflow = makeTriageWorkflow(id: id.uuidString)
    workflow.phase = .active
    workflow.currentStage = stage
    workflow.stageReferences = [
        .init(
            stage: stage,
            attempt: 0,
            hermesTaskID: taskID,
            idempotencyKey: "opshub:workflow:\(stage.rawValue):0",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    ]
    return workflow
}

private func task(id: String) -> HermesKanbanTask {
    .fixture(
        id: id,
        request: .init(
            title: id,
            body: "",
            assignee: "architect",
            workspacePath: "/tmp/repo",
            priority: 1,
            idempotencyKey: id
        )
    )
}

private func task(
    id: String,
    title: String,
    status: HermesKanbanStatus,
    priority: KanbanPriority,
    createdAt: Int?
) -> HermesKanbanTask {
    .init(
        id: id,
        title: title,
        body: "",
        assignee: "developer",
        status: status,
        priority: priority.hermesValue,
        tenant: nil,
        workspaceKind: "dir",
        workspacePath: "/tmp/\(id)",
        branchName: nil,
        projectID: nil,
        createdBy: "fixture",
        createdAt: createdAt,
        startedAt: nil,
        completedAt: nil,
        result: nil
    )
}
