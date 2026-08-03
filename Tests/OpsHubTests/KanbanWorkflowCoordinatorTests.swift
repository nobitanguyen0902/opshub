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
        let gate = KanbanWorkflowMutationGate()
        let harness = makeCoordinatorHarness(mutationGate: gate)
        let draft = try await harness.coordinator.createDraft(makeDraftInput())
        await harness.hermes.suspendNextCreate()

        let firstStart = Task { try await harness.coordinator.start(workflowID: draft.id) }
        await harness.hermes.waitForCreateRequest()
        let secondStart = Task { try await harness.coordinator.start(workflowID: draft.id) }
        await gate.waitForQueuedMutation()
        await harness.hermes.releaseSuspendedCreate()

        _ = try await firstStart.value
        await XCTAssertThrowsErrorAsync(try await secondStart.value) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidPhase(.active))
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.assignee, "architect")
    }

    func testConcurrentDraftAndStartPreserveBothWorkflowSnapshots() async throws {
        let gate = KanbanWorkflowMutationGate()
        let triage = makeTriageWorkflow()
        let harness = makeCoordinatorHarness(workflows: [triage], mutationGate: gate)
        await harness.hermes.suspendNextCreate()

        let start = Task { try await harness.coordinator.start(workflowID: triage.id) }
        await harness.hermes.waitForCreateRequest()
        let createDraft = Task {
            try await harness.coordinator.createDraft(
                KanbanDraftInput(
                    title: "Second task", objective: "Second objective", acceptanceCriteria: ["Second criterion"],
                    workspacePath: "/tmp/repo", priority: .normal
                )
            )
        }
        await gate.waitForQueuedMutation()
        await harness.hermes.releaseSuspendedCreate()

        let started = try await start.value
        let draft = try await createDraft.value
        let workflows = await harness.store.load()
        XCTAssertEqual(workflows.count, 2)
        XCTAssertEqual(workflows.first(where: { $0.id == started.id })?.phase, .active)
        XCTAssertEqual(workflows.first(where: { $0.id == started.id })?.stageReferences.count, 1)
        XCTAssertEqual(workflows.first(where: { $0.id == draft.id })?.phase, .triage)
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
        let gate = KanbanWorkflowMutationGate()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes, mutationGate: gate)
        await hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady))
        await hermes.suspendNextCreate()

        let firstRefresh = Task { try await harness.coordinator.refresh() }
        await hermes.waitForCreateRequest()
        let secondRefresh = Task { try await harness.coordinator.refresh() }
        await gate.waitForQueuedMutation()
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

    func testRefreshDoesNotConsumeStaleTerminalRunWhileTaskIsRunning() async throws {
        let workflow = makeActiveWorkflow()
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        let stale = detail(for: workflow, stage: .architect, handoff: .architectReady)
        await hermes.setDetail(HermesKanbanTaskDetail(
            task: stale.task.replacing(status: .running), latestSummary: stale.latestSummary,
            parents: stale.parents, children: stale.children, comments: stale.comments,
            events: stale.events, runs: stale.runs
        ))

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

        let refreshed = try await harness.coordinator.refresh()
        XCTAssertEqual(refreshed[0].phase, .needsAttention)
        XCTAssertNotNil(refreshed[0].attentionReason)
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testArchitectApprovalRequiredDoesNotCreateDeveloper() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let metadata = HermesRunMetadata(
            schemaVersion: 1, outcome: "approval_required", summary: "Breaking API", risks: ["breaking API"],
            changedFiles: nil, verification: nil, findings: nil
        )
        await harness.hermes.setDetail(detail(for: workflow, stage: .architect, metadata: metadata))

        let refreshed = try await harness.coordinator.refresh()

        XCTAssertEqual(refreshed[0].phase, .approvalRequired)
        XCTAssertNil(refreshed[0].currentStage)
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testApprovalCreatesDeveloperWithInitialAttempt() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .approvalRequired
        workflow.currentStage = nil
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let approval = HermesRunMetadata(
            schemaVersion: 1, outcome: "approval_required", summary: "Breaking API", risks: ["breaking API"],
            changedFiles: nil, verification: nil, findings: nil
        )
        await harness.hermes.setDetail(detail(for: workflow, stage: .architect, metadata: approval))

        let approved = try await harness.coordinator.approve(workflowID: workflow.id)

        XCTAssertEqual(approved.phase, .active)
        XCTAssertEqual(approved.currentStage, .developer)
        XCTAssertEqual(approved.stageReferences.last?.attempt, 0)
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.last?.idempotencyKey, stageKey(workflowID: workflow.id, stage: .developer, attempt: 0))
        XCTAssertTrue(requests.last?.body.contains("Architect handoff: Breaking API") == true)
    }

    func testApprovalRejectsMismatchedTerminalProfileWithoutCreatingDeveloper() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .approvalRequired
        workflow.currentStage = nil
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let metadata = HermesRunMetadata(
            schemaVersion: 1, outcome: "approval_required", summary: "Breaking API", risks: ["breaking API"],
            changedFiles: nil, verification: nil, findings: nil
        )
        let reference = try XCTUnwrap(workflow.stageReferences.last)
        let task = HermesKanbanTask(
            id: reference.hermesTaskID, title: workflow.title, body: nil, assignee: "architect", status: .done,
            priority: workflow.priority.hermesValue, tenant: nil, workspaceKind: "dir", workspacePath: workflow.workspacePath,
            branchName: nil, projectID: nil, createdBy: "opshub", createdAt: 1, startedAt: 1, completedAt: 2, result: nil
        )
        await harness.hermes.setDetail(HermesKanbanTaskDetail(
            task: task, latestSummary: nil, parents: [], children: [], comments: [], events: [], runs: [.init(
                id: 1, profile: "developer", stepKey: nil, status: "completed", outcome: "completed", summary: nil,
                error: nil, metadata: metadata, workerPID: nil, startedAt: 1, endedAt: 2
            )]
        ))

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.approve(workflowID: workflow.id)) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidHandoff(.architect))
        }
        let requests = await harness.hermes.createdRequests
        let stored = await harness.store.load()
        XCTAssertTrue(requests.isEmpty)
        XCTAssertEqual(stored, [workflow])
    }

    func testTerminalArchitectBlockedMovesToNeedsAttentionAndCannotRetry() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let metadata = HermesRunMetadata(
            schemaVersion: 1, outcome: "blocked", summary: "Cannot proceed", risks: [],
            changedFiles: nil, verification: nil, findings: nil
        )
        await harness.hermes.setDetail(detail(for: workflow, stage: .architect, metadata: metadata))

        let result = try await harness.coordinator.refresh()[0]

        XCTAssertEqual(result.phase, .needsAttention)
        await XCTAssertThrowsErrorAsync(try await harness.coordinator.retry(workflowID: workflow.id)) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidPhase(.needsAttention))
        }
    }

    func testTerminalDeveloperBlockedAndFailedMoveToNeedsAttentionAndCannotRetry() async throws {
        for outcome in ["blocked", "failed"] {
            var workflow = makeActiveWorkflow()
            workflow.currentStage = .developer
            workflow.stageReferences = [KanbanStageReference(
                stage: .developer, attempt: 0, hermesTaskID: "developer-task",
                idempotencyKey: stageKey(workflowID: workflow.id, stage: .developer, attempt: 0),
                createdAt: Date(timeIntervalSince1970: 1)
            )]
            let harness = makeCoordinatorHarness(workflows: [workflow])
            let metadata = HermesRunMetadata(
                schemaVersion: 1, outcome: outcome, summary: "Cannot proceed", risks: nil,
                changedFiles: [], verification: [], findings: nil
            )
            await harness.hermes.setDetail(detail(for: workflow, stage: .developer, metadata: metadata))

            let result = try await harness.coordinator.refresh()[0]

            XCTAssertEqual(result.phase, .needsAttention, "\(outcome) must not become Hermes-retryable")
            await XCTAssertThrowsErrorAsync(try await harness.coordinator.retry(workflowID: workflow.id)) { error in
                XCTAssertEqual(error as? KanbanWorkflowError, .invalidPhase(.needsAttention))
            }
        }
    }

    func testTerminalReviewerBlockedMovesToNeedsAttentionAndCannotRetry() async throws {
        var workflow = makeActiveWorkflow()
        workflow.currentStage = .reviewer
        workflow.stageReferences = [KanbanStageReference(
            stage: .reviewer, attempt: 0, hermesTaskID: "reviewer-task",
            idempotencyKey: stageKey(workflowID: workflow.id, stage: .reviewer, attempt: 0),
            createdAt: Date(timeIntervalSince1970: 1)
        )]
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let metadata = HermesRunMetadata(
            schemaVersion: 1, outcome: "blocked", summary: "Cannot proceed", risks: nil,
            changedFiles: nil, verification: nil, findings: []
        )
        await harness.hermes.setDetail(detail(for: workflow, stage: .reviewer, metadata: metadata))

        let result = try await harness.coordinator.refresh()[0]

        XCTAssertEqual(result.phase, .needsAttention)
        await XCTAssertThrowsErrorAsync(try await harness.coordinator.retry(workflowID: workflow.id)) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .invalidPhase(.needsAttention))
        }
    }

    func testThirdChangesRequestedStopsAtNeedsAttention() async throws {
        var workflow = makeActiveWorkflow()
        workflow.currentStage = .reviewer
        workflow.repairCount = 2
        workflow.stageReferences = [KanbanStageReference(
            stage: .reviewer, attempt: 2, hermesTaskID: "reviewer-task",
            idempotencyKey: stageKey(workflowID: workflow.id, stage: .reviewer, attempt: 2),
            createdAt: Date(timeIntervalSince1970: 1)
        )]
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let metadata = HermesRunMetadata(
            schemaVersion: 1, outcome: "changes_requested", summary: "Still failing", risks: nil,
            changedFiles: nil, verification: nil, findings: ["still failing"]
        )
        await harness.hermes.setDetail(detail(for: workflow, stage: .reviewer, metadata: metadata))

        let refreshed = try await harness.coordinator.refresh()

        XCTAssertEqual(refreshed[0].phase, .needsAttention)
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.count, 0)
    }

    func testChangesRequestedCreatesDeveloperRepairAndReviewerUsesSameAttempt() async throws {
        var workflow = makeActiveWorkflow()
        workflow.currentStage = .reviewer
        workflow.stageReferences = [KanbanStageReference(
            stage: .reviewer, attempt: 0, hermesTaskID: "reviewer-task",
            idempotencyKey: stageKey(workflowID: workflow.id, stage: .reviewer, attempt: 0),
            createdAt: Date(timeIntervalSince1970: 1)
        )]
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)
        let changes = HermesRunMetadata(
            schemaVersion: 1, outcome: "changes_requested", summary: "Fix it", risks: nil,
            changedFiles: nil, verification: nil, findings: ["missing test"]
        )
        await hermes.setDetail(detail(for: workflow, stage: .reviewer, metadata: changes))

        let repairing = try await harness.coordinator.refresh()[0]
        XCTAssertEqual(repairing.currentStage, .developer)
        XCTAssertEqual(repairing.repairCount, 1)
        XCTAssertEqual(repairing.stageReferences.last?.attempt, 1)

        await hermes.setDetail(detail(for: repairing, stage: .developer, handoff: .developerCompleted))
        let reviewing = try await harness.coordinator.refresh()[0]
        XCTAssertEqual(reviewing.currentStage, .reviewer)
        XCTAssertEqual(reviewing.stageReferences.last?.attempt, 1)
    }

    func testCancelRunningTaskBlocksThenRetryRestoresActiveWithoutChangingRepairCount() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(runningDetail(for: workflow, stage: .architect))

        let cancelled = try await harness.coordinator.cancel(workflowID: workflow.id)
        XCTAssertEqual(cancelled.phase, .blocked)
        XCTAssertEqual(cancelled.repairCount, 0)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertEqual(reclaimCalls, ["architect-task"])
        XCTAssertEqual(blockCalls, ["architect-task"])

        let retried = try await harness.coordinator.retry(workflowID: workflow.id)
        XCTAssertEqual(retried.phase, .active)
        XCTAssertEqual(retried.currentStage, .architect)
        XCTAssertEqual(retried.repairCount, 0)
        let unblockCalls = await harness.hermes.unblockCalls
        XCTAssertEqual(unblockCalls, ["architect-task"])
    }

    func testRetryLocalApprovalCancellationRestoresGateWithoutUnblockingHermes() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .blocked
        workflow.currentStage = nil
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .cancel, stage: nil, attempt: 0, idempotencyKey: "opshub:test:cancel:0",
            previousPhase: .approvalRequired, startedAt: Date(timeIntervalSince1970: 1)
        )
        workflow.cancellationReason = "Cancelled by user"
        let harness = makeCoordinatorHarness(workflows: [workflow])

        let retried = try await harness.coordinator.retry(workflowID: workflow.id)

        XCTAssertEqual(retried.phase, .approvalRequired)
        XCTAssertNil(retried.pendingTransition)
        let unblockCalls = await harness.hermes.unblockCalls
        XCTAssertTrue(unblockCalls.isEmpty)
    }

    func testResumePendingCancellationBlocksTaskAfterReclaimCheckpoint() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .blocked
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .cancel, stage: .architect, attempt: 0, idempotencyKey: "opshub:test:cancel:0",
            previousPhase: .active, cancelReclaimAttempted: false, cancelReclaimed: false,
            cancelPreReclaimStatus: .running, startedAt: Date(timeIntervalSince1970: 1)
        )
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(runningDetail(for: workflow, stage: .architect))

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertEqual(resumed[0].phase, .blocked)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertEqual(reclaimCalls, ["architect-task"])
        XCTAssertEqual(blockCalls, ["architect-task"])
    }

    func testResumePendingCreateReusesIdempotencyKeyAndPersistsReference() async throws {
        var workflow = makeTriageWorkflow()
        workflow.phase = .active
        workflow.currentStage = .developer
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .createStage, stage: .developer, attempt: 0,
            idempotencyKey: stageKey(workflowID: workflow.id, stage: .developer, attempt: 0),
            previousPhase: .active, startedAt: Date(timeIntervalSince1970: 1)
        )
        let harness = makeCoordinatorHarness(workflows: [workflow])

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertNil(resumed[0].pendingTransition)
        XCTAssertEqual(resumed[0].stageReferences.last?.stage, .developer)
        let requests = await harness.hermes.createdRequests
        XCTAssertEqual(requests.last?.idempotencyKey, stageKey(workflowID: workflow.id, stage: .developer, attempt: 0))
    }

    func testResumePendingApprovalWithAlreadyCreatedDeveloperPersistsReference() async throws {
        var workflow = makeTriageWorkflow()
        workflow.phase = .active
        workflow.currentStage = .developer
        let key = stageKey(workflowID: workflow.id, stage: .developer, attempt: 0)
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .approve, stage: .developer, attempt: 0, idempotencyKey: key,
            previousPhase: .approvalRequired, previousHandoffSummary: "Breaking API",
            startedAt: Date(timeIntervalSince1970: 1)
        )
        let hermes = StubHermesKanbanService()
        let expectedRequest = HermesTaskCreateRequest(
            title: workflow.title,
            body: developerPromptBody(for: workflow, handoff: "Breaking API"),
            assignee: "developer", workspacePath: workflow.workspacePath,
            priority: workflow.priority.hermesValue, idempotencyKey: key
        )
        _ = try await hermes.createTask(expectedRequest)
        let harness = makeCoordinatorHarness(workflows: [workflow], hermes: hermes)

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertNil(resumed[0].pendingTransition)
        XCTAssertEqual(resumed[0].stageReferences.last?.hermesTaskID, "task-1")
        let requests = await hermes.createdRequests
        XCTAssertEqual(requests.count, 1)
        let attempts = await hermes.createAttempts
        XCTAssertEqual(attempts, [expectedRequest, expectedRequest])
    }

    func testMalformedHandoffMovesOnlyThatWorkflowToNeedsAttentionAndRefreshContinues() async throws {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
        let first = makeActiveWorkflow(workspacePath: "/tmp/first", id: firstID)
        var second = makeActiveWorkflow(workspacePath: "/tmp/second", id: secondID)
        second.stageReferences = [.init(
            stage: .architect, attempt: 0, hermesTaskID: "architect-task-2",
            idempotencyKey: stageKey(workflowID: second.id, stage: .architect, attempt: 0),
            createdAt: Date(timeIntervalSince1970: 1)
        )]
        let hermes = StubHermesKanbanService()
        let harness = makeCoordinatorHarness(workflows: [first, second], hermes: hermes)
        let malformed = HermesRunMetadata(
            schemaVersion: 1, outcome: "ready", summary: "Missing risks", risks: nil,
            changedFiles: nil, verification: nil, findings: nil
        )
        await hermes.setDetail(detail(for: first, stage: .architect, metadata: malformed))
        await hermes.setDetail(detail(for: second, stage: .architect, handoff: .architectReady))

        let refreshed = try await harness.coordinator.refresh()

        XCTAssertEqual(refreshed[0].phase, .needsAttention)
        XCTAssertNotNil(refreshed[0].attentionReason)
        XCTAssertEqual(refreshed[1].phase, .active)
        XCTAssertEqual(refreshed[1].currentStage, .developer)
    }

    func testDoneTaskWithLatestNonterminalRunMovesToNeedsAttention() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let terminal = detail(for: workflow, stage: .architect, handoff: .architectReady)
        let running = HermesKanbanRun(
            id: 2, profile: "architect", stepKey: nil, status: "running", outcome: nil, summary: nil,
            error: nil, metadata: nil, workerPID: nil, startedAt: 3, endedAt: nil
        )
        await harness.hermes.setDetail(.init(
            task: terminal.task, latestSummary: nil, parents: [], children: [], comments: [], events: [],
            runs: terminal.runs + [running]
        ))

        let refreshed = try await harness.coordinator.refresh()

        XCTAssertEqual(refreshed[0].phase, .needsAttention)
        let requests = await harness.hermes.createdRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testDoneTaskDoesNotConsumeOlderArchitectRunWhenLatestRunHasDifferentProfile() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let terminal = detail(for: workflow, stage: .architect, handoff: .architectReady)
        let newerWrongProfile = HermesKanbanRun(
            id: 2, profile: "developer", stepKey: nil, status: "completed", outcome: "completed", summary: nil,
            error: nil, metadata: terminal.runs[0].metadata, workerPID: nil, startedAt: 3, endedAt: 4
        )
        await harness.hermes.setDetail(.init(
            task: terminal.task, latestSummary: nil, parents: [], children: [], comments: [], events: [],
            runs: terminal.runs + [newerWrongProfile]
        ))

        let refreshed = try await harness.coordinator.refresh()

        XCTAssertEqual(refreshed[0].phase, .needsAttention)
        let requests = await harness.hermes.createdRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancelTerminalStageUsesLocalSemanticsAndRetryDoesNotUnblock() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(detail(for: workflow, stage: .architect, handoff: .architectReady))

        let cancelled = try await harness.coordinator.cancel(workflowID: workflow.id)

        XCTAssertEqual(cancelled.phase, .blocked)
        XCTAssertNil(cancelled.pendingTransition)
        XCTAssertEqual(cancelled.cancellationPreviousPhase, .active)
        XCTAssertEqual(cancelled.cancellationRequiresHermesUnblock, false)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertTrue(reclaimCalls.isEmpty)
        XCTAssertTrue(blockCalls.isEmpty)

        let retried = try await harness.coordinator.retry(workflowID: workflow.id)
        XCTAssertEqual(retried.phase, .active)
        let unblockCalls = await harness.hermes.unblockCalls
        XCTAssertTrue(unblockCalls.isEmpty)
    }

    func testSuccessfulCancellationClearsPendingTransition() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(runningDetail(for: workflow, stage: .architect))

        let cancelled = try await harness.coordinator.cancel(workflowID: workflow.id)

        XCTAssertNil(cancelled.pendingTransition)
        XCTAssertEqual(cancelled.cancellationPreviousPhase, .active)
        XCTAssertEqual(cancelled.cancellationRequiresHermesUnblock, true)
    }

    func testStartRejectsWorkspaceReservedByUnfinishedCancellation() async throws {
        let cancellingID = UUID(uuidString: "00000000-0000-0000-0000-000000000021")!
        var cancelling = makeActiveWorkflow(id: cancellingID)
        cancelling.phase = .needsAttention
        cancelling.pendingTransition = KanbanPendingTransition(
            kind: .cancel, stage: .architect, attempt: 0, idempotencyKey: "cancel",
            previousPhase: .active, cancelReclaimed: true, startedAt: Date(timeIntervalSince1970: 1)
        )
        let draft = makeTriageWorkflow(id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!)
        let harness = makeCoordinatorHarness(workflows: [cancelling, draft])

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .workspaceAlreadyActive(cancelling.id))
        }
        let requests = await harness.hermes.createdRequests
        XCTAssertTrue(requests.isEmpty)
    }

    func testPartialCancellationRecoveryDoesNotReclaimTwice() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(runningDetail(for: workflow, stage: .architect))
        await harness.hermes.failNextBlock()

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.cancel(workflowID: workflow.id)) { _ in }
        let partialValues = await harness.store.load()
        let partial = try XCTUnwrap(partialValues.first)
        XCTAssertEqual(partial.phase, .needsAttention)
        XCTAssertEqual(partial.pendingTransition?.kind, .cancel)
        XCTAssertEqual(partial.pendingTransition?.cancelReclaimed, true)

        let recovered = try await harness.coordinator.recoverCancellation(workflowID: workflow.id)

        XCTAssertEqual(recovered.phase, .blocked)
        XCTAssertNil(recovered.pendingTransition)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertEqual(reclaimCalls, ["architect-task"])
        XCTAssertEqual(blockCalls, ["architect-task", "architect-task"])
    }

    func testAutomaticResumeAfterReclaimSideEffectDoesNotReclaimTwice() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .blocked
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .cancel, stage: .architect, attempt: 0, idempotencyKey: "cancel",
            previousPhase: .active, cancelReclaimAttempted: true, cancelReclaimed: false,
            cancelPreReclaimStatus: .running, startedAt: Date(timeIntervalSince1970: 1)
        )
        workflow.cancellationReason = "Cancelled by user"
        let harness = makeCoordinatorHarness(workflows: [workflow])
        let afterReclaim = runningDetail(for: workflow, stage: .architect)
        await harness.hermes.setDetail(.init(
            task: afterReclaim.task.replacing(status: .ready), latestSummary: nil,
            parents: [], children: [], comments: [], events: [], runs: []
        ))

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertEqual(resumed[0].phase, .blocked)
        XCTAssertNil(resumed[0].pendingTransition)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertTrue(reclaimCalls.isEmpty)
        XCTAssertEqual(blockCalls, ["architect-task"])
    }

    func testAutomaticResumeDoesNotRepeatAmbiguousReclaimAttempt() async throws {
        var workflow = makeActiveWorkflow()
        workflow.phase = .blocked
        workflow.pendingTransition = KanbanPendingTransition(
            kind: .cancel, stage: .architect, attempt: 0, idempotencyKey: "cancel",
            previousPhase: .active, cancelReclaimAttempted: true, cancelReclaimed: false,
            cancelPreReclaimStatus: .running, startedAt: Date(timeIntervalSince1970: 1)
        )
        workflow.cancellationReason = "Cancelled by user"
        let harness = makeCoordinatorHarness(workflows: [workflow])
        await harness.hermes.setDetail(runningDetail(for: workflow, stage: .architect))

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertEqual(resumed[0].phase, .needsAttention)
        XCTAssertEqual(resumed[0].pendingTransition?.cancelReclaimAttempted, true)
        XCTAssertEqual(resumed[0].pendingTransition?.cancelReclaimed, false)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertTrue(reclaimCalls.isEmpty)
        XCTAssertTrue(blockCalls.isEmpty)
    }

    func testAutomaticResumeTreatsLegacyCancellationWithoutAttemptMetadataAsAmbiguous() async throws {
        let historicalTransitionJSON = #"""
        {
          "kind": "cancel",
          "stage": "architect",
          "attempt": 0,
          "idempotencyKey": "cancel",
          "previousPhase": "active",
          "cancelReclaimed": false,
          "startedAt": "1970-01-01T00:00:01Z"
        }
        """#
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let legacyTransition = try decoder.decode(
            KanbanPendingTransition.self,
            from: try XCTUnwrap(historicalTransitionJSON.data(using: .utf8))
        )
        XCTAssertNil(legacyTransition.cancelReclaimAttempted)

        let cancellingID = UUID(uuidString: "00000000-0000-0000-0000-000000000041")!
        var cancelling = makeActiveWorkflow(id: cancellingID)
        cancelling.phase = .blocked
        cancelling.pendingTransition = legacyTransition
        cancelling.cancellationReason = "Cancelled by user"
        let draft = makeTriageWorkflow(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!
        )
        let harness = makeCoordinatorHarness(workflows: [cancelling, draft])
        await harness.hermes.setDetail(runningDetail(for: cancelling, stage: .architect))

        let resumed = try await harness.coordinator.resumePendingTransitions()

        XCTAssertEqual(resumed[0].phase, .needsAttention)
        XCTAssertNil(resumed[0].pendingTransition?.cancelReclaimAttempted)
        XCTAssertEqual(resumed[0].pendingTransition?.cancelReclaimed, false)
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertTrue(reclaimCalls.isEmpty)
        XCTAssertTrue(blockCalls.isEmpty)
        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .workspaceAlreadyActive(cancelling.id))
        }

        let recovered = try await harness.coordinator.recoverCancellation(workflowID: cancelling.id)
        XCTAssertEqual(recovered.phase, .blocked)
        XCTAssertNil(recovered.pendingTransition)
        let recoveredReclaimCalls = await harness.hermes.reclaimCalls
        let recoveredBlockCalls = await harness.hermes.blockCalls
        XCTAssertEqual(recoveredReclaimCalls, ["architect-task"])
        XCTAssertEqual(recoveredBlockCalls, ["architect-task"])
    }

    func testCancellationRecoveryRejectsWorkflowWithoutPendingCancelMutation() async throws {
        let workflow = makeActiveWorkflow()
        let harness = makeCoordinatorHarness(workflows: [workflow])

        await XCTAssertThrowsErrorAsync(
            try await harness.coordinator.recoverCancellation(workflowID: workflow.id)
        ) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .unsafeRecovery)
        }
        let reclaimCalls = await harness.hermes.reclaimCalls
        let blockCalls = await harness.hermes.blockCalls
        XCTAssertTrue(reclaimCalls.isEmpty)
        XCTAssertTrue(blockCalls.isEmpty)
    }

    func testCreateStageRequiresValidPostCreateShowBeforePersistingReference() async throws {
        let harness = makeCoordinatorHarness()
        let draft = try await harness.coordinator.createDraft(makeDraftInput())
        await harness.hermes.invalidateNextCreatedTaskIdentity()

        await XCTAssertThrowsErrorAsync(try await harness.coordinator.start(workflowID: draft.id)) { error in
            XCTAssertEqual(error as? KanbanWorkflowError, .unsafeRecovery)
        }
        let storedValues = await harness.store.load()
        let stored = try XCTUnwrap(storedValues.first)
        XCTAssertEqual(stored.phase, .active)
        XCTAssertEqual(stored.pendingTransition?.kind, .createStage)
        XCTAssertTrue(stored.stageReferences.isEmpty)
    }

    func testStartAllowedAfterTerminalMalformedHandoffNeedsAttention() async throws {
        let malformedID = UUID(uuidString: "00000000-0000-0000-0000-000000000031")!
        let draftID = UUID(uuidString: "00000000-0000-0000-0000-000000000032")!
        let malformedWorkflow = makeActiveWorkflow(id: malformedID)
        let draft = makeTriageWorkflow(id: draftID)
        let harness = makeCoordinatorHarness(workflows: [malformedWorkflow, draft])
        let malformed = HermesRunMetadata(
            schemaVersion: 1, outcome: "ready", summary: "Missing risks", risks: nil,
            changedFiles: nil, verification: nil, findings: nil
        )
        await harness.hermes.setDetail(detail(for: malformedWorkflow, stage: .architect, metadata: malformed))

        let refreshed = try await harness.coordinator.refresh()
        XCTAssertEqual(refreshed[0].phase, .needsAttention)

        let started = try await harness.coordinator.start(workflowID: draft.id)
        XCTAssertEqual(started.phase, .active)
        XCTAssertEqual(started.currentStage, .architect)
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
    workspaceValidator: StubWorkspaceValidator = StubWorkspaceValidator(),
    mutationGate: KanbanWorkflowMutationGate = KanbanWorkflowMutationGate()
) -> CoordinatorHarness {
    let store = InMemoryWorkflowStore(workflows)
    let coordinator = KanbanWorkflowCoordinator(
        store: store,
        hermes: hermes,
        workspaceValidator: workspaceValidator,
        now: { Date(timeIntervalSince1970: 1) },
        mutationGate: mutationGate
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

private func makeTriageWorkflow(
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
) -> KanbanWorkflow {
    KanbanWorkflow(
        schemaVersion: 1,
        id: id,
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

private func makeActiveWorkflow(
    workspacePath: String = "/tmp/repo",
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
) -> KanbanWorkflow {
    var workflow = makeTriageWorkflow(id: id)
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
    private(set) var createAttempts: [HermesTaskCreateRequest] = []
    private(set) var profileChecks: [String] = []
    private(set) var reclaimCalls: [String] = []
    private(set) var blockCalls: [String] = []
    private(set) var unblockCalls: [String] = []
    private var details: [String: HermesKanbanTaskDetail] = [:]
    private var tasksByIdempotencyKey: [String: HermesKanbanTask] = [:]
    private var suspendNextCreateRequest = false
    private var suspendedCreate: CheckedContinuation<Void, Never>?
    private var createRequestWaiters: [CheckedContinuation<Void, Never>] = []
    private var blockFailuresRemaining = 0
    private var invalidateNextCreatedTask = false
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
        createAttempts.append(request)
        if let existing = tasksByIdempotencyKey[request.idempotencyKey] {
            return existing
        }
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
        let task = HermesKanbanTask.fixture(id: "task-\(createdRequests.count)", request: request)
        tasksByIdempotencyKey[request.idempotencyKey] = task
        let detailTask = invalidateNextCreatedTask ? task.replacing(assignee: "wrong-profile") : task
        invalidateNextCreatedTask = false
        details[task.id] = HermesKanbanTaskDetail(
            task: detailTask, latestSummary: nil, parents: [], children: [], comments: [], events: [], runs: []
        )
        return task
    }
    func reclaim(taskID: String, reason: String) async throws { reclaimCalls.append(taskID) }
    func block(taskID: String, reason: String) async throws {
        blockCalls.append(taskID)
        if blockFailuresRemaining > 0 {
            blockFailuresRemaining -= 1
            throw StubHermesFailure.blockFailed
        }
        try updateStatus(taskID: taskID, status: .blocked)
    }
    func unblock(taskID: String, reason: String) async throws {
        unblockCalls.append(taskID)
        try updateStatus(taskID: taskID, status: .ready)
    }
    func setDetail(_ detail: HermesKanbanTaskDetail) { details[detail.task.id] = detail }
    func failNextBlock() { blockFailuresRemaining += 1 }
    func invalidateNextCreatedTaskIdentity() { invalidateNextCreatedTask = true }
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

    private func updateStatus(taskID: String, status: HermesKanbanStatus) throws {
        let detail = try XCTUnwrap(details[taskID])
        details[taskID] = HermesKanbanTaskDetail(
            task: detail.task.replacing(status: status), latestSummary: detail.latestSummary,
            parents: detail.parents, children: detail.children, comments: detail.comments,
            events: detail.events, runs: detail.runs
        )
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

    func replacing(status: HermesKanbanStatus) -> Self {
        HermesKanbanTask(
            id: id, title: title, body: body, assignee: assignee, status: status, priority: priority,
            tenant: tenant, workspaceKind: workspaceKind, workspacePath: workspacePath, branchName: branchName,
            projectID: projectID, createdBy: createdBy, createdAt: createdAt, startedAt: startedAt,
            completedAt: completedAt, result: result
        )
    }

    func replacing(assignee: String?) -> Self {
        HermesKanbanTask(
            id: id, title: title, body: body, assignee: assignee, status: status, priority: priority,
            tenant: tenant, workspaceKind: workspaceKind, workspacePath: workspacePath, branchName: branchName,
            projectID: projectID, createdBy: createdBy, createdAt: createdAt, startedAt: startedAt,
            completedAt: completedAt, result: result
        )
    }
}

private enum StubHermesFailure: LocalizedError {
    case blockFailed

    var errorDescription: String? { "Block failed" }
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

private func runningDetail(for workflow: KanbanWorkflow, stage: KanbanStage) -> HermesKanbanTaskDetail {
    let reference = workflow.stageReferences.last { $0.stage == stage }!
    return HermesKanbanTaskDetail(
        task: HermesKanbanTask(
            id: reference.hermesTaskID, title: workflow.title, body: nil, assignee: stage.rawValue,
            status: .running, priority: workflow.priority.hermesValue, tenant: nil, workspaceKind: "dir",
            workspacePath: workflow.workspacePath, branchName: nil, projectID: nil, createdBy: "opshub",
            createdAt: 1, startedAt: 1, completedAt: nil, result: nil
        ),
        latestSummary: nil, parents: [], children: [], comments: [], events: [], runs: []
    )
}

private func developerPromptBody(for workflow: KanbanWorkflow, handoff: String) -> String {
    """
    Objective: \(workflow.objective)

    Acceptance criteria:
    \(workflow.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\\n"))

    You are the Developer. You may modify only the selected workspace and must preserve unrelated user changes.

    Architect handoff: \(handoff)

    Complete this Hermes task with metadata JSON schemaVersion=1.
    Architect outcomes: ready | approval_required | blocked; include risks[].
    Developer outcomes: completed | blocked | failed; include changedFiles[] and verification[].
    Reviewer outcomes: approved | changes_requested | blocked; include findings[].
    Do not claim success unless the required work and verification are complete.
    """
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
