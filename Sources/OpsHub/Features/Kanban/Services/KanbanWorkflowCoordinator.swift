import Foundation

protocol KanbanWorkflowCoordinating: Sendable {
    func workflows() async throws -> [KanbanWorkflow]
    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow
    func start(workflowID: UUID) async throws -> KanbanWorkflow
    func refresh() async throws -> [KanbanWorkflow]
    func approve(workflowID: UUID) async throws -> KanbanWorkflow
    func cancel(workflowID: UUID) async throws -> KanbanWorkflow
    func retry(workflowID: UUID) async throws -> KanbanWorkflow
    func resumePendingTransitions() async throws -> [KanbanWorkflow]
}

enum KanbanWorkflowError: LocalizedError, Equatable {
    case workflowNotFound(UUID)
    case invalidPhase(KanbanPhase)
    case invalidDraft
    case invalidHandoff(KanbanStage)
    case missingCurrentTask
    case unsafeRecovery

    var errorDescription: String? {
        switch self {
        case .workflowNotFound:
            "Kanban workflow was not found."
        case .invalidPhase:
            "This Kanban workflow cannot perform that action in its current phase."
        case .invalidDraft:
            "Provide a title, objective, and at least one acceptance criterion."
        case .invalidHandoff:
            "The current stage returned an invalid handoff."
        case .missingCurrentTask:
            "The current Hermes task could not be found for this workflow."
        case .unsafeRecovery:
            "This workflow needs attention before it can be recovered safely."
        }
    }
}

actor KanbanWorkflowCoordinator: KanbanWorkflowCoordinating {
    private let store: any KanbanWorkflowStoring
    private let hermes: any HermesKanbanServicing
    private let workspaceValidator: any KanbanWorkspaceValidating
    private let now: @Sendable () -> Date
    private let mutationGate: KanbanWorkflowMutationGate

    init(
        store: any KanbanWorkflowStoring,
        hermes: any HermesKanbanServicing,
        workspaceValidator: any KanbanWorkspaceValidating,
        now: @escaping @Sendable () -> Date = Date.init,
        mutationGate: KanbanWorkflowMutationGate = KanbanWorkflowMutationGate()
    ) {
        self.store = store
        self.hermes = hermes
        self.workspaceValidator = workspaceValidator
        self.now = now
        self.mutationGate = mutationGate
    }

    func workflows() async throws -> [KanbanWorkflow] {
        try await store.load()
    }

    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow {
        try await mutationGate.run { [self] in
            try await createDraftLocked(input)
        }
    }

    private func createDraftLocked(_ input: KanbanDraftInput) async throws -> KanbanWorkflow {
        let title = input.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let objective = input.objective.trimmingCharacters(in: .whitespacesAndNewlines)
        let workspacePath = input.workspacePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let acceptanceCriteria = input.acceptanceCriteria
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !title.isEmpty, !objective.isEmpty, !workspacePath.isEmpty, !acceptanceCriteria.isEmpty else {
            throw KanbanWorkflowError.invalidDraft
        }

        let canonicalWorkspace = try await workspaceValidator.validateDraftPath(
            URL(fileURLWithPath: workspacePath)
        )
        let timestamp = now()
        let workflow = KanbanWorkflow(
            schemaVersion: KanbanWorkflow.currentSchemaVersion,
            id: UUID(),
            title: title,
            objective: objective,
            acceptanceCriteria: acceptanceCriteria,
            workspacePath: canonicalWorkspace.path,
            priority: input.priority,
            phase: .triage,
            currentStage: nil,
            repairCount: 0,
            stageReferences: [],
            pendingTransition: nil,
            cancellationReason: nil,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        var current = try await store.load()
        current.append(workflow)
        try await store.save(current)
        return workflow
    }

    func start(workflowID: UUID) async throws -> KanbanWorkflow {
        try await mutationGate.run { [self] in
            try await startLocked(workflowID: workflowID)
        }
    }

    private func startLocked(workflowID: UUID) async throws -> KanbanWorkflow {
        let current = try await store.load()
        guard let index = current.firstIndex(where: { $0.id == workflowID }) else {
            throw KanbanWorkflowError.workflowNotFound(workflowID)
        }
        let workflow = current[index]
        guard workflow.phase == .triage else {
            throw KanbanWorkflowError.invalidPhase(workflow.phase)
        }

        let canonicalWorkspace = try await workspaceValidator.validateStart(
            URL(fileURLWithPath: workflow.workspacePath)
        )
        let canonicalPath = canonicalWorkspace.standardizedFileURL.resolvingSymlinksInPath().path
        if let activeWorkflow = current.first(where: {
            $0.id != workflowID && ($0.phase == .active || $0.phase == .approvalRequired) &&
                Self.canonicalPath($0.workspacePath) == canonicalPath
        }) {
            throw KanbanStartGuardError.workspaceAlreadyActive(activeWorkflow.id)
        }

        guard await hermes.isAvailable() else {
            throw KanbanStartGuardError.hermesUnavailable
        }
        for profile in [KanbanStage.architect, .developer, .reviewer] {
            guard await hermes.profileExists(profile.rawValue) else {
                throw KanbanStartGuardError.missingProfile(profile.rawValue)
            }
        }
        guard await hermes.isGatewayRunning() else {
            throw KanbanStartGuardError.gatewayStopped
        }

        var updated = workflow
        updated.workspacePath = canonicalPath
        updated.phase = .active
        updated.currentStage = .architect
        return try await createStage(
            stage: .architect,
            attempt: 0,
            previousHandoffSummary: nil,
            workflow: updated,
            replacingAt: index,
            in: current
        )
    }

    func refresh() async throws -> [KanbanWorkflow] {
        try await mutationGate.run { [self] in
            try await refreshLocked()
        }
    }

    func approve(workflowID: UUID) async throws -> KanbanWorkflow {
        try await mutationGate.run { [self] in
            let workflows = try await store.load()
            guard let index = workflows.firstIndex(where: { $0.id == workflowID }) else {
                throw KanbanWorkflowError.workflowNotFound(workflowID)
            }
            let workflow = workflows[index]
            guard workflow.phase == .approvalRequired else {
                throw KanbanWorkflowError.invalidPhase(workflow.phase)
            }

            return try await createStage(
                stage: .developer,
                attempt: workflow.repairCount,
                previousHandoffSummary: nil,
                workflow: workflow,
                replacingAt: index,
                in: workflows,
                pendingKind: .approve
            )
        }
    }

    func cancel(workflowID: UUID) async throws -> KanbanWorkflow {
        try await mutationGate.run { [self] in
            let workflows = try await store.load()
            guard let index = workflows.firstIndex(where: { $0.id == workflowID }) else {
                throw KanbanWorkflowError.workflowNotFound(workflowID)
            }
            let workflow = workflows[index]
            guard workflow.phase == .active || workflow.phase == .approvalRequired else {
                throw KanbanWorkflowError.invalidPhase(workflow.phase)
            }

            var cancelled = workflow
            cancelled.phase = .blocked
            cancelled.pendingTransition = KanbanPendingTransition(
                kind: .cancel,
                stage: workflow.currentStage,
                attempt: workflow.repairCount,
                idempotencyKey: "opshub:\(workflow.id.uuidString.lowercased()):cancel:\(workflow.repairCount)",
                previousPhase: workflow.phase,
                startedAt: now()
            )
            cancelled.cancellationReason = "Cancelled by user"
            cancelled.updatedAt = now()
            try await persist(cancelled, replacingAt: index, in: workflows)

            guard let reference = Self.currentReference(in: workflow) else {
                return cancelled
            }
            try await hermes.reclaim(taskID: reference.hermesTaskID, reason: "Cancelled by user")
            do {
                try await hermes.block(taskID: reference.hermesTaskID, reason: "Cancelled by user")
                let detail = try await hermes.taskDetail(id: reference.hermesTaskID)
                guard detail.task.status == .blocked else {
                    throw KanbanWorkflowError.unsafeRecovery
                }
                return cancelled
            } catch {
                var needsAttention = cancelled
                needsAttention.phase = .needsAttention
                needsAttention.cancellationReason = "Reclaimed but failed to block: \(error.localizedDescription)"
                needsAttention.updatedAt = now()
                try await persist(needsAttention, replacingAt: index, in: workflows)
                throw error
            }
        }
    }

    func retry(workflowID: UUID) async throws -> KanbanWorkflow {
        try await mutationGate.run { [self] in
            let workflows = try await store.load()
            guard let index = workflows.firstIndex(where: { $0.id == workflowID }) else {
                throw KanbanWorkflowError.workflowNotFound(workflowID)
            }
            return try await retryLocked(workflow: workflows[index], replacingAt: index, in: workflows)
        }
    }

    func resumePendingTransitions() async throws -> [KanbanWorkflow] {
        try await mutationGate.run { [self] in
            var workflows = try await store.load()
            for index in workflows.indices {
                guard let transition = workflows[index].pendingTransition else { continue }
                let workflow = workflows[index]
                do {
                    let recovered: KanbanWorkflow
                    switch transition.kind {
                    case .createStage, .approve:
                        recovered = try await resumeStageCreation(
                            workflow: workflow,
                            transition: transition,
                            replacingAt: index,
                            in: workflows
                        )
                    case .cancel:
                        recovered = try await resumeCancellation(
                            workflow: workflow,
                            transition: transition,
                            replacingAt: index,
                            in: workflows
                        )
                    case .retry:
                        recovered = try await resumeRetry(
                            workflow: workflow,
                            transition: transition,
                            replacingAt: index,
                            in: workflows
                        )
                    }
                    workflows[index] = recovered
                } catch {
                    var needsAttention = workflow
                    needsAttention.phase = .needsAttention
                    needsAttention.updatedAt = now()
                    try await persist(needsAttention, replacingAt: index, in: workflows)
                    workflows[index] = needsAttention
                }
            }
            return try await store.load()
        }
    }

    private func refreshLocked() async throws -> [KanbanWorkflow] {
        var current = try await store.load()
        for index in current.indices {
            let workflow = current[index]
            guard workflow.phase == .active, let stage = workflow.currentStage else {
                continue
            }
            guard let reference = workflow.stageReferences.last(where: { $0.stage == stage }) else {
                throw KanbanWorkflowError.missingCurrentTask
            }

            let detail = try await hermes.taskDetail(id: reference.hermesTaskID)
            guard let run = latestTerminalRun(in: detail.runs), run.profile == stage.rawValue else {
                continue
            }

            let reconciled = try await reconcile(
                workflow: workflow,
                stage: stage,
                metadata: run.metadata,
                replacingAt: index,
                in: current
            )
            current[index] = reconciled
        }
        return current
    }

    private func reconcile(
        workflow: KanbanWorkflow,
        stage: KanbanStage,
        metadata: HermesRunMetadata?,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        guard let metadata else {
            throw KanbanWorkflowError.invalidHandoff(stage)
        }
        switch stage {
        case .architect:
            let handoff = try architectHandoff(from: metadata)
            switch handoff.outcome {
            case .ready:
                return try await createStage(
                    stage: .developer,
                    attempt: workflow.repairCount,
                    previousHandoffSummary: handoff.summary,
                    workflow: workflow,
                    replacingAt: index,
                    in: workflows
                )
            case .approvalRequired:
                var awaitingApproval = workflow
                awaitingApproval.phase = .approvalRequired
                awaitingApproval.currentStage = nil
                awaitingApproval.pendingTransition = nil
                awaitingApproval.updatedAt = now()
                try await persist(awaitingApproval, replacingAt: index, in: workflows)
                return awaitingApproval
            case .blocked:
                return try await block(workflow, replacingAt: index, in: workflows)
            }

        case .developer:
            let handoff = try developerHandoff(from: metadata)
            switch handoff.outcome {
            case .completed:
                return try await createStage(
                    stage: .reviewer,
                    attempt: workflow.repairCount,
                    previousHandoffSummary: handoff.summary,
                    workflow: workflow,
                    replacingAt: index,
                    in: workflows
                )
            case .blocked, .failed:
                return try await block(workflow, replacingAt: index, in: workflows)
            }

        case .reviewer:
            let handoff = try reviewerHandoff(from: metadata)
            switch handoff.outcome {
            case .approved:
                var completed = workflow
                completed.phase = .done
                completed.currentStage = nil
                completed.pendingTransition = nil
                completed.updatedAt = now()
                try await persist(completed, replacingAt: index, in: workflows)
                return completed
            case .changesRequested:
                guard workflow.repairCount < 2 else {
                    var needsAttention = workflow
                    needsAttention.phase = .needsAttention
                    needsAttention.currentStage = nil
                    needsAttention.updatedAt = now()
                    try await persist(needsAttention, replacingAt: index, in: workflows)
                    return needsAttention
                }
                var repair = workflow
                repair.repairCount += 1
                return try await createStage(
                    stage: .developer,
                    attempt: repair.repairCount,
                    previousHandoffSummary: handoff.summary,
                    workflow: repair,
                    replacingAt: index,
                    in: workflows
                )
            case .blocked:
                return try await block(workflow, replacingAt: index, in: workflows)
            }
        }
    }

    private func createStage(
        stage: KanbanStage,
        attempt: Int,
        previousHandoffSummary: String?,
        workflow: KanbanWorkflow,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow],
        pendingKind: KanbanPendingTransition.Kind = .createStage
    ) async throws -> KanbanWorkflow {
        let idempotencyKey = stageKey(workflowID: workflow.id, stage: stage, attempt: attempt)
        var pending = workflow
        pending.phase = .active
        pending.currentStage = stage
        pending.pendingTransition = KanbanPendingTransition(
            kind: pendingKind,
            stage: stage,
            attempt: attempt,
            idempotencyKey: idempotencyKey,
            previousPhase: workflow.phase,
            startedAt: now()
        )
        pending.updatedAt = now()
        var persisted = workflows
        persisted[index] = pending
        try await store.save(persisted)

        let request = HermesTaskCreateRequest(
            title: workflow.title,
            body: stagePrompt(for: stage, workflow: workflow, previousHandoffSummary: previousHandoffSummary),
            assignee: stage.rawValue,
            workspacePath: workflow.workspacePath,
            priority: workflow.priority.hermesValue,
            idempotencyKey: idempotencyKey
        )
        let task = try await hermes.createTask(request)

        var completed = pending
        completed.stageReferences.append(KanbanStageReference(
            stage: stage,
            attempt: attempt,
            hermesTaskID: task.id,
            idempotencyKey: idempotencyKey,
            createdAt: now()
        ))
        completed.pendingTransition = nil
        completed.updatedAt = now()
        persisted[index] = completed
        try await store.save(persisted)
        return completed
    }

    private func retryLocked(
        workflow: KanbanWorkflow,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        guard workflow.phase == .blocked else {
            throw KanbanWorkflowError.invalidPhase(workflow.phase)
        }
        let previousPhase = workflow.pendingTransition?.previousPhase ?? .active
        guard let reference = Self.currentReference(in: workflow) else {
            var restored = workflow
            restored.phase = previousPhase
            restored.pendingTransition = nil
            restored.cancellationReason = nil
            restored.updatedAt = now()
            try await persist(restored, replacingAt: index, in: workflows)
            return restored
        }

        var pending = workflow
        pending.pendingTransition = KanbanPendingTransition(
            kind: .retry,
            stage: reference.stage,
            attempt: reference.attempt,
            idempotencyKey: "opshub:\(workflow.id.uuidString.lowercased()):retry:\(reference.attempt)",
            previousPhase: previousPhase,
            startedAt: now()
        )
        pending.updatedAt = now()
        try await persist(pending, replacingAt: index, in: workflows)
        guard let transition = pending.pendingTransition else {
            throw KanbanWorkflowError.unsafeRecovery
        }
        return try await resumeRetry(
            workflow: pending,
            transition: transition,
            replacingAt: index,
            in: workflows
        )
    }

    private func resumeStageCreation(
        workflow: KanbanWorkflow,
        transition: KanbanPendingTransition,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        guard let stage = transition.stage, let attempt = transition.attempt else {
            throw KanbanWorkflowError.unsafeRecovery
        }
        let request = HermesTaskCreateRequest(
            title: workflow.title,
            body: stagePrompt(for: stage, workflow: workflow, previousHandoffSummary: nil),
            assignee: stage.rawValue,
            workspacePath: workflow.workspacePath,
            priority: workflow.priority.hermesValue,
            idempotencyKey: transition.idempotencyKey
        )
        let task: HermesKanbanTask
        if let reference = workflow.stageReferences.last(where: { $0.idempotencyKey == transition.idempotencyKey }) {
            guard reference.stage == stage, reference.attempt == attempt else {
                throw KanbanWorkflowError.unsafeRecovery
            }
            task = try await hermes.taskDetail(id: reference.hermesTaskID).task
        } else {
            task = try await hermes.createTask(request)
            _ = try await hermes.taskDetail(id: task.id)
        }

        var recovered = workflow
        recovered.phase = .active
        recovered.currentStage = stage
        if !recovered.stageReferences.contains(where: { $0.idempotencyKey == transition.idempotencyKey }) {
            recovered.stageReferences.append(KanbanStageReference(
                stage: stage,
                attempt: attempt,
                hermesTaskID: task.id,
                idempotencyKey: transition.idempotencyKey,
                createdAt: now()
            ))
        }
        recovered.pendingTransition = nil
        recovered.updatedAt = now()
        try await persist(recovered, replacingAt: index, in: workflows)
        return recovered
    }

    private func resumeCancellation(
        workflow: KanbanWorkflow,
        transition: KanbanPendingTransition,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        guard let reference = Self.currentReference(in: workflow) else {
            return workflow
        }
        let detail = try await hermes.taskDetail(id: reference.hermesTaskID)
        switch detail.task.status {
        case .blocked:
            return workflow
        case .ready, .running, .review:
            try await hermes.reclaim(taskID: reference.hermesTaskID, reason: "Cancelled by user")
            try await hermes.block(taskID: reference.hermesTaskID, reason: "Cancelled by user")
            let blocked = try await hermes.taskDetail(id: reference.hermesTaskID)
            guard blocked.task.status == .blocked else { throw KanbanWorkflowError.unsafeRecovery }
            return workflow
        default:
            throw KanbanWorkflowError.unsafeRecovery
        }
    }

    private func resumeRetry(
        workflow: KanbanWorkflow,
        transition: KanbanPendingTransition,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        guard let reference = Self.currentReference(in: workflow) else {
            var restored = workflow
            restored.phase = transition.previousPhase ?? .active
            restored.pendingTransition = nil
            restored.cancellationReason = nil
            restored.updatedAt = now()
            try await persist(restored, replacingAt: index, in: workflows)
            return restored
        }
        let current = try await hermes.taskDetail(id: reference.hermesTaskID)
        if current.task.status == .blocked {
            try await hermes.unblock(taskID: reference.hermesTaskID, reason: "Retry requested by user")
        }
        let unblocked = try await hermes.taskDetail(id: reference.hermesTaskID)
        guard unblocked.task.status == .ready || unblocked.task.status == .running else {
            throw KanbanWorkflowError.unsafeRecovery
        }
        var restored = workflow
        restored.phase = .active
        restored.currentStage = reference.stage
        restored.pendingTransition = nil
        restored.cancellationReason = nil
        restored.updatedAt = now()
        try await persist(restored, replacingAt: index, in: workflows)
        return restored
    }

    private func block(
        _ workflow: KanbanWorkflow,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws -> KanbanWorkflow {
        var blocked = workflow
        blocked.phase = .blocked
        blocked.updatedAt = now()
        try await persist(blocked, replacingAt: index, in: workflows)
        return blocked
    }

    private static func currentReference(in workflow: KanbanWorkflow) -> KanbanStageReference? {
        guard let stage = workflow.currentStage else { return nil }
        return workflow.stageReferences.last(where: { $0.stage == stage })
    }

    private func persist(
        _ workflow: KanbanWorkflow,
        replacingAt index: Int,
        in workflows: [KanbanWorkflow]
    ) async throws {
        var persisted = workflows
        persisted[index] = workflow
        try await store.save(persisted)
    }

    private func latestTerminalRun(in runs: [HermesKanbanRun]) -> HermesKanbanRun? {
        runs
            .filter { $0.endedAt != nil }
            .max { lhs, rhs in
                (lhs.endedAt ?? 0, lhs.id) < (rhs.endedAt ?? 0, rhs.id)
            }
    }

    private func stagePrompt(
        for stage: KanbanStage,
        workflow: KanbanWorkflow,
        previousHandoffSummary: String?
    ) -> String {
        let criteria = workflow.acceptanceCriteria.map { "- \($0)" }.joined(separator: "\n")
        let previous = previousHandoffSummary.map { "\n\n\(previousHandoffLabel(for: stage)): \($0)" } ?? ""
        let roleInstruction: String
        switch stage {
        case .architect:
            roleInstruction = "You are the Architect. This stage is read-only; inspect and plan without modifying the workspace."
        case .developer:
            roleInstruction = "You are the Developer. You may modify only the selected workspace and must preserve unrelated user changes."
        case .reviewer:
            roleInstruction = "You are the Reviewer. This stage is read-only; inspect the implementation and verification without modifying the workspace."
        }

        return """
        Objective: \(workflow.objective)

        Acceptance criteria:
        \(criteria)

        \(roleInstruction)\(previous)

        Complete this Hermes task with metadata JSON schemaVersion=1.
        Architect outcomes: ready | approval_required | blocked; include risks[].
        Developer outcomes: completed | blocked | failed; include changedFiles[] and verification[].
        Reviewer outcomes: approved | changes_requested | blocked; include findings[].
        Do not claim success unless the required work and verification are complete.
        """
    }

    private func previousHandoffLabel(for stage: KanbanStage) -> String {
        switch stage {
        case .architect: "Previous handoff"
        case .developer: "Architect handoff"
        case .reviewer: "Developer handoff"
        }
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
}

actor KanbanWorkflowMutationGate {
    private var isRunning = false
    private var waiters: [(UUID, CheckedContinuation<Bool, Never>)] = []
    private var queueObservers: [CheckedContinuation<Void, Never>] = []

    func run<T: Sendable>(
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        guard await acquire() else {
            throw CancellationError()
        }
        defer { release() }
        return try await operation()
    }

    private func acquire() async -> Bool {
        guard !isRunning else {
            let waiterID = UUID()
            return await withTaskCancellationHandler(operation: {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(returning: false)
                        return
                    }
                    waiters.append((waiterID, continuation))
                    let observers = queueObservers
                    queueObservers.removeAll()
                    observers.forEach { $0.resume() }
                }
            }, onCancel: {
                Task { await self.cancelWaiter(id: waiterID) }
            })
        }
        isRunning = true
        return true
    }

    private func release() {
        guard !waiters.isEmpty else {
            isRunning = false
            return
        }
        let waiter = waiters.removeFirst()
        waiter.1.resume(returning: true)
    }

    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.0 == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.1.resume(returning: false)
    }

    func waitForQueuedMutation() async {
        guard waiters.isEmpty else { return }
        await withCheckedContinuation { continuation in
            queueObservers.append(continuation)
        }
    }
}

func stageKey(workflowID: UUID, stage: KanbanStage, attempt: Int) -> String {
    "opshub:\(workflowID.uuidString.lowercased()):\(stage.rawValue):\(attempt)"
}

func architectHandoff(from metadata: HermesRunMetadata) throws -> ArchitectHandoff {
    guard
        let version = metadata.schemaVersion,
        let rawOutcome = metadata.outcome,
        let outcome = ArchitectOutcome(rawValue: rawOutcome),
        let summary = metadata.summary,
        let risks = metadata.risks,
        version == KanbanWorkflow.currentSchemaVersion
    else {
        throw KanbanWorkflowError.invalidHandoff(.architect)
    }
    return ArchitectHandoff(schemaVersion: version, outcome: outcome, summary: summary, risks: risks)
}

func developerHandoff(from metadata: HermesRunMetadata) throws -> DeveloperHandoff {
    guard
        let version = metadata.schemaVersion,
        let rawOutcome = metadata.outcome,
        let outcome = DeveloperOutcome(rawValue: rawOutcome),
        let summary = metadata.summary,
        let changedFiles = metadata.changedFiles,
        let verification = metadata.verification,
        version == KanbanWorkflow.currentSchemaVersion
    else {
        throw KanbanWorkflowError.invalidHandoff(.developer)
    }
    return DeveloperHandoff(
        schemaVersion: version,
        outcome: outcome,
        summary: summary,
        changedFiles: changedFiles,
        verification: verification
    )
}

func reviewerHandoff(from metadata: HermesRunMetadata) throws -> ReviewerHandoff {
    guard
        let version = metadata.schemaVersion,
        let rawOutcome = metadata.outcome,
        let outcome = ReviewerOutcome(rawValue: rawOutcome),
        let summary = metadata.summary,
        let findings = metadata.findings,
        version == KanbanWorkflow.currentSchemaVersion
    else {
        throw KanbanWorkflowError.invalidHandoff(.reviewer)
    }
    return ReviewerHandoff(schemaVersion: version, outcome: outcome, summary: summary, findings: findings)
}

private extension ArchitectHandoff {
    init(schemaVersion: Int, outcome: ArchitectOutcome, summary: String, risks: [String]) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.summary = summary
        self.risks = risks
    }
}

private extension DeveloperHandoff {
    init(
        schemaVersion: Int,
        outcome: DeveloperOutcome,
        summary: String,
        changedFiles: [String],
        verification: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.summary = summary
        self.changedFiles = changedFiles
        self.verification = verification
    }
}

private extension ReviewerHandoff {
    init(schemaVersion: Int, outcome: ReviewerOutcome, summary: String, findings: [String]) {
        self.schemaVersion = schemaVersion
        self.outcome = outcome
        self.summary = summary
        self.findings = findings
    }
}
