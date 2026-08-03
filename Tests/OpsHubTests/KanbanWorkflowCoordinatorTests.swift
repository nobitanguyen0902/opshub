import Foundation
import XCTest
@testable import OpsHub

final class KanbanWorkflowCoordinatorTests: XCTestCase {
    func testCreateDraftPersistsTriageWithoutCreatingHermesTask() async throws {
        let harness = makeCoordinatorHarness()

        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        XCTAssertEqual(draft.phase, .triage)
        XCTAssertNil(draft.currentStage)
        let requests = await harness.hermes.createdRequests
        let storedWorkflows = await harness.store.load()
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(storedWorkflows, [draft])
    }

    func testCreateDraftTrimsInputAndStoresCanonicalWorkspacePath() async throws {
        let canonicalPath = "/tmp/canonical-repo"
        let harness = makeCoordinatorHarness(
            workspaceValidator: StubWorkspaceValidator(draftResult: URL(fileURLWithPath: canonicalPath))
        )
        let input = KanbanDraftInput(
            title: "  Task  ",
            objective: "  Objective  ",
            acceptanceCriteria: [" Criterion ", "   "],
            workspacePath: "/tmp/input-repo",
            priority: .high
        )

        let draft = try await harness.coordinator.createDraft(input)

        XCTAssertEqual(draft.title, "Task")
        XCTAssertEqual(draft.objective, "Objective")
        XCTAssertEqual(draft.acceptanceCriteria, ["Criterion"])
        XCTAssertEqual(draft.workspacePath, canonicalPath)
        XCTAssertEqual(draft.priority, .high)
    }

    func testCreateDraftDoesNotPersistWhenInputIsInvalid() async throws {
        let existing = makeTriageWorkflow()
        let harness = makeCoordinatorHarness(workflows: [existing])
        let invalidInput = KanbanDraftInput(
            title: " ", objective: "Objective", acceptanceCriteria: ["Criterion"],
            workspacePath: "/tmp/repo", priority: .normal
        )

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.createDraft(invalidInput)) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidDraft)
        }
        let storedWorkflows = await harness.store.load()
        XCTAssertEqual(storedWorkflows, [existing])
    }

    func testCreateDraftDoesNotPersistWhenWorkspaceValidationFails() async throws {
        let existing = makeTriageWorkflow()
        let harness = makeCoordinatorHarness(
            workflows: [existing],
            workspaceValidator: StubWorkspaceValidator(draftError: KanbanStartGuardError.notGitRepository)
        )

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.createDraft(makeDraftInput())) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .notGitRepository)
        }
        let storedWorkflows = await harness.store.load()
        XCTAssertEqual(storedWorkflows, [existing])
    }

    func testStartCreatesArchitectStageAfterAllGuardsPass() async throws {
        let harness = makeCoordinatorHarness()
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        let started = try await harness.coordinator.start(workflowID: draft.id)

        XCTAssertEqual(started.phase, .active)
        XCTAssertEqual(started.currentStage, .architect)
        XCTAssertEqual(started.stageReferences.count, 1)
        let requests = await harness.hermes.createdRequests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.assignee, "architect")
        XCTAssertEqual(
            request.idempotencyKey,
            "opshub:\(draft.id.uuidString.lowercased()):architect:0"
        )
        XCTAssertEqual(request.workspacePath, "/tmp/repo")
        XCTAssertEqual(request.priority, KanbanPriority.normal.hermesValue)
        let body = request.body
        XCTAssertTrue(body.contains("read-only"))
        XCTAssertTrue(body.contains("Complete this Hermes task with metadata JSON schemaVersion=1."))
    }

    func testStartDoesNotCreateTaskWhenWorkspaceValidationFails() async throws {
        let harness = makeCoordinatorHarness(
            workspaceValidator: StubWorkspaceValidator(startError: KanbanStartGuardError.dirtyWorkingTree([" M File.swift"]))
        )
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .dirtyWorkingTree([" M File.swift"]))
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testStartDoesNotCreateTaskWhenWorkspaceAlreadyActive() async throws {
        let active = makeActiveWorkflow(workspacePath: "/tmp/repo")
        let harness = makeCoordinatorHarness(workflows: [active])
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .workspaceAlreadyActive(active.id))
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testStartDoesNotCreateTaskWhenHermesIsUnavailable() async throws {
        let harness = makeCoordinatorHarness(hermes: StubHermesKanbanService(isAvailable: false))
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .hermesUnavailable)
        }
        let requests = await harness.hermes.createdRequests
        let profileChecks = await harness.hermes.profileChecks
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(profileChecks, [])
    }

    func testStartDoesNotCreateTaskWhenProfileIsMissing() async throws {
        let harness = makeCoordinatorHarness(
            hermes: StubHermesKanbanService(profiles: ["architect", "developer"])
        )
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .missingProfile("reviewer"))
        }
        let requests = await harness.hermes.createdRequests
        let profileChecks = await harness.hermes.profileChecks
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(profileChecks, ["architect", "developer", "reviewer"])
    }

    func testStartDoesNotCreateTaskWhenGatewayIsStopped() async throws {
        let harness = makeCoordinatorHarness(hermes: StubHermesKanbanService(gatewayRunning: false))
        let draft = try await harness.coordinator.createDraft(makeDraftInput())

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .gatewayStopped)
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testConcurrentStartsCreateOnlyOneArchitectTask() async throws {
        let harness = makeCoordinatorHarness()
        let draft = try await harness.coordinator.createDraft(makeDraftInput())
        await harness.hermes.suspendNextCreate()

        let firstStart = Task { try await harness.coordinator.start(workflowID: draft.id) }
        await harness.hermes.waitForCreateRequest()
        let secondStart = Task { try await harness.coordinator.start(workflowID: draft.id) }
        await harness.hermes.releaseSuspendedCreate()

        _ = try await firstStart.value
        await XCTAssertThrowsErrorAsync(try await secondStart.value) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidPhase(.active))
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.assignee, "architect")
    }

    func testRefreshAdvancesArchitectDeveloperReviewerAndMarksDone() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        await hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady))

        let afterArchitect = try await harness.coordinator.refresh()
        XCTAssertEqual(afterArchitect[0].currentStage, .developer)
        let architectRequests = await hermes.createdRequests
        let developerRequest = try XCTUnwrap(architectRequests.last)
        XCTAssertEqual(developerRequest.assignee, "developer")
        XCTAssertTrue(developerRequest.body.contains("Architect handoff: Architecture is ready."))

        let developerWorkflow = try XCTUnwrap(afterArchitect.first)
        await hermes.setDetail(detail(for: developerWorkflow, stage: .developer, handoff: .developerCompleted))
        let afterDeveloper = try await harness.coordinator.refresh()
        XCTAssertEqual(afterDeveloper[0].currentStage, .reviewer)
        let developerRequests = await hermes.createdRequests
        let reviewerRequest = try XCTUnwrap(developerRequests.last)
        XCTAssertEqual(reviewerRequest.assignee, "reviewer")
        XCTAssertTrue(reviewerRequest.body.contains("Developer handoff: Implementation completed."))

        let reviewerWorkflow = try XCTUnwrap(afterDeveloper.first)
        await hermes.setDetail(detail(for: reviewerWorkflow, stage: .reviewer, handoff: .reviewerApproved))
        let done = try await harness.coordinator.refresh()
        XCTAssertEqual(done[0].phase, .done)
        XCTAssertNil(done[0].currentStage)
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 2)
    }

    func testRefreshDoesNotCreateDeveloperTwiceForSameArchitectRun() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        await hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady))

        let afterFirstRefresh = try await harness.coordinator.refresh()
        await hermes.setDetail(detail(for: afterFirstRefresh[0], stage: .developer, endedAt: nil))
        _ = try await harness.coordinator.refresh()

        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.assignee, "developer")
    }

    func testConcurrentRefreshesCreateOnlyOneDeveloperTask() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        await hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady))
        await hermes.suspendNextCreate()

        let firstRefresh = Task { try await harness.coordinator.refresh() }
        await hermes.waitForCreateRequest()
        let secondRefresh = Task { try await harness.coordinator.refresh() }
        let developerWorkflow = workflowWithStage(
            workflow,
            stage: .developer,
            taskID: "task-1",
            idempotencyKey: stageKey(workflowID: workflow.id, stage: .developer, attempt: 0)
        )
        await hermes.setDetail(detail(for: developerWorkflow, stage: .developer, endedAt: nil))
        await hermes.releaseSuspendedCreate()

        _ = try await firstRefresh.value
        _ = try await secondRefresh.value
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.assignee, "developer")
    }

    func testRefreshRejectsNonTerminalOrMismatchedRunWithoutCreatingTask() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        await hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady, endedAt: nil))

        let refreshed = try await harness.coordinator.refresh()
        XCTAssertEqual(refreshed, [workflow])
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testRefreshRejectsIncompleteArchitectMetadata() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        let invalid = HermesRunMetadata(
            schemaVersion: 1, outcome: "ready", summary: "Ready", risks: nil,
            changedFiles: nil, verification: nil, findings: nil
        )
        await hermes.setDetail(detail(for: workflow, stage: .architect, metadata: invalid))

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.refresh()) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidHandoff(.architect))
        }
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }
}

private struct CoordinatorHarness {
    let coordinator: KanbanWorkflowCoordinator
    let hermes: StubHermesKanbanService
    let store: InMemoryWorkflowStore
}

private func makeCoordinatorHarness(
    workflows: [KanbanWorkflow] = [],
    hermes: StubHermesKanbanService = StubHermesKanbanService(),
    workspaceValidator: StubWorkspaceValidator = StubWorkspaceValidator()
) -> CoordinatorHarness {
    let store = InMemoryWorkflowStore(workflows)
    let coordinator = KanbanWorkflowCoordinator(
        store: store,
        hermes: hermes,
        workspaceValidator: workspaceValidator,
        now: { Date(timeIntervalSince1970: 1) }
    )
    return CoordinatorHarness(coordinator: coordinator, hermes: hermes, store: store)
}

private func makeDraftInput() -> KanbanDraftInput {
    KanbanDraftInput(
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal
    )
}

private func makeTriageWorkflow() -> KanbanWorkflow {
    KanbanWorkflow(
        schemaVersion: 1,
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
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

private func makeActiveWorkflow(workspacePath: String = "/tmp/repo") -> KanbanWorkflow {
    var workflow = makeTriageWorkflow()
    workflow.phase = .active
    workflow.currentStage = .architect
    workflow.workspacePath = workspacePath
    workflow.stageReferences = [
        KanbanStageReference(
            stage: .architect,
            attempt: 0,
            hermesTaskID: "architect-task",
            idempotencyKey: "opshub:\(workflow.id.uuidString.lowercased()):architect:0",
            createdAt: Date(timeIntervalSince1970: 1)
        )
    ]
    return workflow
}

private func workflowWithStage(
    _ workflow: KanbanWorkflow,
    stage: KanbanStage,
    taskID: String,
    idempotencyKey: String
) -> KanbanWorkflow {
    var updated = workflow
    updated.currentStage = stage
    updated.stageReferences.append(KanbanStageReference(
        stage: stage,
        attempt: 0,
        hermesTaskID: taskID,
        idempotencyKey: idempotencyKey,
        createdAt: Date(timeIntervalSince1970: 1)
    ))
    return updated
}

private actor InMemoryWorkflowStore: KanbanWorkflowStoring {
    private var value: [KanbanWorkflow]

    init(_ value: [KanbanWorkflow] = []) { self.value = value }

    func load() -> [KanbanWorkflow] { value }
    func save(_ workflows: [KanbanWorkflow]) { value = workflows }
}

private struct StubWorkspaceValidator: KanbanWorkspaceValidating {
    let draftResult: URL
    let startResult: URL
    let draftError: Error?
    let startError: Error?

    init(
        draftResult: URL = URL(fileURLWithPath: "/tmp/repo"),
        startResult: URL = URL(fileURLWithPath: "/tmp/repo"),
        draftError: Error? = nil,
        startError: Error? = nil
    ) {
        self.draftResult = draftResult
        self.startResult = startResult
        self.draftError = draftError
        self.startError = startError
    }

    func validateDraftPath(_ url: URL) async throws -> URL {
        if let draftError { throw draftError }
        return draftResult.standardizedFileURL.resolvingSymlinksInPath()
    }

    func validateStart(_ url: URL) async throws -> URL {
        if let startError { throw startError }
        return startResult.standardizedFileURL.resolvingSymlinksInPath()
    }
}

private actor StubHermesKanbanService: HermesKanbanServicing {
    private(set) var createdRequests: [HermesTaskCreateRequest] = []
    private(set) var profileChecks: [String] = []
    private var details: [String: HermesKanbanTaskDetail] = [:]
    private var suspendNextCreateRequest = false
    private var suspendedCreate: CheckedContinuation<Void, Never>?
    private var createRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private let available: Bool
    private let profiles: Set<String>
    private let gatewayRunning: Bool

    init(
        isAvailable: Bool = true,
        profiles: Set<String> = ["architect", "developer", "reviewer"],
        gatewayRunning: Bool = true
    ) {
        available = isAvailable
        self.profiles = profiles
        self.gatewayRunning = gatewayRunning
    }

    func listTasks() async throws -> [HermesKanbanTask] { details.values.map(\.task) }
    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail { try XCTUnwrap(details[id]) }
    func runs(taskID: String) async throws -> [HermesKanbanRun] { try XCTUnwrap(details[taskID]).runs }
    func log(taskID: String, tailBytes: Int) async throws -> String { "" }
    func isAvailable() async -> Bool { available }
    func profileExists(_ profile: String) async -> Bool {
        profileChecks.append(profile)
        return profiles.contains(profile)
    }
    func isGatewayRunning() async -> Bool { gatewayRunning }
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask {
        createdRequests.append(request)
        let waiters = createRequestWaiters
        createRequestWaiters.removeAll()
        waiters.forEach { $0.resume() }
        if suspendNextCreateRequest {
            suspendNextCreateRequest = false
            await withCheckedContinuation { continuation in
                suspendedCreate = continuation
            }
        }
        return HermesKanbanTask.fixture(id: "task-\(createdRequests.count)", request: request)
    }
    func reclaim(taskID: String, reason: String) async throws {}
    func block(taskID: String, reason: String) async throws {}
    func unblock(taskID: String, reason: String) async throws {}
    func setDetail(_ detail: HermesKanbanTaskDetail) { details[detail.task.id] = detail }
    func suspendNextCreate() { suspendNextCreateRequest = true }
    func releaseSuspendedCreate() {
        suspendedCreate?.resume()
        suspendedCreate = nil
    }
    func waitForCreateRequest() async {
        guard createdRequests.isEmpty else { return }
        await withCheckedContinuation { continuation in
            createRequestWaiters.append(continuation)
        }
    }
}

private extension HermesKanbanTask {
    static func fixture(id: String, request: HermesTaskCreateRequest) -> Self {
        HermesKanbanTask(
            id: id, title: request.title, body: request.body, assignee: request.assignee,
            status: .ready, priority: request.priority, tenant: nil, workspaceKind: "dir",
            workspacePath: request.workspacePath, branchName: nil, projectID: nil,
            createdBy: "opshub", createdAt: 1, startedAt: nil, completedAt: nil, result: nil
        )
    }
}

private enum TestHandoff {
    case architectReady, developerCompleted, reviewerApproved
}

private func detail(
    for workflow: KanbanWorkflow,
    stage: KanbanStage,
    handoff: TestHandoff? = nil,
    metadata: HermesRunMetadata? = nil,
    endedAt: Int? = 2
) -> HermesKanbanTaskDetail {
    let reference = workflow.stageReferences.last { $0.stage == stage }!
    let resolvedMetadata: HermesRunMetadata?
    switch handoff {
    case .architectReady:
        resolvedMetadata = HermesRunMetadata(schemaVersion: 1, outcome: "ready", summary: "Architecture is ready.", risks: [], changedFiles: nil, verification: nil, findings: nil)
    case .developerCompleted:
        resolvedMetadata = HermesRunMetadata(schemaVersion: 1, outcome: "completed", summary: "Implementation completed.", risks: nil, changedFiles: ["File.swift"], verification: ["swift test"], findings: nil)
    case .reviewerApproved:
        resolvedMetadata = HermesRunMetadata(schemaVersion: 1, outcome: "approved", summary: "Approved.", risks: nil, changedFiles: nil, verification: nil, findings: [])
    case nil:
        resolvedMetadata = metadata
    }
    let task = HermesKanbanTask(
        id: reference.hermesTaskID, title: workflow.title, body: nil, assignee: stage.rawValue,
        status: .done, priority: workflow.priority.hermesValue, tenant: nil, workspaceKind: "dir",
        workspacePath: workflow.workspacePath, branchName: nil, projectID: nil,
        createdBy: "opshub", createdAt: 1, startedAt: 1, completedAt: endedAt, result: nil
    )
    let run = HermesKanbanRun(
        id: 1, profile: stage.rawValue, stepKey: nil, status: "completed", outcome: nil,
        summary: nil, error: nil, metadata: resolvedMetadata, workerPID: nil, startedAt: 1, endedAt: endedAt
    )
    return HermesKanbanTaskDetail(
        task: task, latestSummary: nil, parents: [], children: [], comments: [], events: [], runs: [run]
    )
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
