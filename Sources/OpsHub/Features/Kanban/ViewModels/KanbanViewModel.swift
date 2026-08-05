import Foundation

@MainActor final class KanbanViewModel: ObservableObject {
    @Published private(set) var snapshot: KanbanBoardSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeAction: KanbanAction?
    @Published var selectedCardID: KanbanCardID? {
        didSet { updateSelectedHermesTaskID() }
    }
    @Published var isPresentingNewTask = false
    @Published var selectedDetail: KanbanTaskDetail?
    @Published private(set) var selectedHermesTaskID: String?
    @Published private(set) var selectedHermesDetail: HermesKanbanTaskDetail?
    @Published private(set) var selectedLog: String?

    var isLoading: Bool { isRefreshing }

    var headerMetadata: String {
        guard let snapshot else {
            return isRefreshing ? "source=Hermes · loading" : "source=Hermes · awaiting refresh"
        }
        return "source=Hermes · tasks=\(snapshot.cards.count)"
    }

    private let hermes: any HermesKanbanServicing
    private let coordinator: any KanbanWorkflowCoordinating
    private let workspaceValidator: any KanbanWorkspaceValidating
    private let sleeper: @Sendable (Duration) async throws -> Void
    private var detailRequestID: UUID?
    private var logRequestID: UUID?

    init(
        hermes: any HermesKanbanServicing = HermesKanbanService(),
        coordinator: (any KanbanWorkflowCoordinating)? = nil,
        workspaceValidator: any KanbanWorkspaceValidating = KanbanWorkspaceValidator(),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.hermes = hermes
        self.workspaceValidator = workspaceValidator
        self.coordinator = coordinator ?? KanbanWorkflowCoordinator(
            store: FileKanbanWorkflowStore(),
            hermes: hermes,
            workspaceValidator: KanbanWorkspaceValidator()
        )
        self.sleeper = sleeper
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            async let workflows = coordinator.refresh()
            async let hermesTasks = hermes.listTasks()
            snapshot = KanbanBoardSnapshot(
                cards: makeCards(workflows: try await workflows, hermesTasks: try await hermesTasks),
                loadedAt: Date()
            )
            updateSelectedHermesTaskID()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDraft(_ input: KanbanDraftInput) async -> Bool {
        await performMutation(.createDraft) {
            _ = try await self.coordinator.createDraft(input)
        }
    }

    func validateDraftWorkspacePath(_ path: String) async throws -> String {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { throw KanbanStartGuardError.missingDirectory }
        return try await workspaceValidator.validateDraftPath(
            URL(fileURLWithPath: trimmedPath)
        ).path
    }

    func startSelected() async {
        await performSelectedMutation(action: .start, requiredAction: .start) { workflowID in
            _ = try await self.coordinator.start(workflowID: workflowID)
        }
    }

    func approveSelected() async {
        await performSelectedMutation(action: .approve, requiredAction: .approve) { workflowID in
            _ = try await self.coordinator.approve(workflowID: workflowID)
        }
    }

    func cancelSelected() async {
        await performSelectedMutation(action: .cancel, requiredAction: .cancel) { workflowID in
            _ = try await self.coordinator.cancel(workflowID: workflowID)
        }
    }

    func retrySelected() async {
        await performSelectedMutation(action: .retry, requiredAction: .retry) { workflowID in
            _ = try await self.coordinator.retry(workflowID: workflowID)
        }
    }

    func retryCancellationRecoverySelected() async {
        await performSelectedMutation(
            action: .retryCancellationRecovery,
            requiredAction: .retryCancellationRecovery
        ) { workflowID in
            _ = try await self.coordinator.recoverCancellation(workflowID: workflowID)
        }
    }

    func loadSelectedDetail() async {
        guard let taskID = selectedHermesTaskID else { return }
        let requestID = UUID()
        detailRequestID = requestID
        do {
            let detail = try await hermes.taskDetail(id: taskID)
            guard shouldPublishDetail(requestID: requestID, taskID: taskID) else { return }
            selectedHermesDetail = detail
            selectedDetail = legacyDetail(from: detail)
            errorMessage = nil
        } catch {
            guard shouldPublishDetail(requestID: requestID, taskID: taskID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadSelectedLog(tailBytes: Int = 64_000) async {
        guard let taskID = selectedHermesTaskID else { return }
        let requestID = UUID()
        logRequestID = requestID
        do {
            let log = try await hermes.log(taskID: taskID, tailBytes: tailBytes)
            guard shouldPublishLog(requestID: requestID, taskID: taskID) else { return }
            selectedLog = log
            errorMessage = nil
        } catch {
            guard shouldPublishLog(requestID: requestID, taskID: taskID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    func autoRefresh() async {
        do {
            _ = try await coordinator.resumePendingTransitions()
        } catch {
            errorMessage = error.localizedDescription
        }
        await refresh()

        while !Task.isCancelled {
            do {
                try await sleeper(.seconds(5))
            } catch is CancellationError {
                return
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // Kept until Task 8 moves the existing board to card selection.
    func select(_ task: KanbanTask) async {
        selectedCardID = snapshot?.cards.first(where: { $0.displayID == task.id })?.id ?? .hermes(task.id)
        await loadSelectedDetail()
    }

    private func performSelectedMutation(
        action: KanbanAction,
        requiredAction: KanbanAvailableAction,
        operation: @escaping @MainActor (UUID) async throws -> Void
    ) async {
        guard case let .workflow(workflowID)? = selectedCardID,
              selectedCard?.availableActions.contains(requiredAction) == true
        else {
            return
        }
        await performMutation(action) {
            try await operation(workflowID)
        }
    }

    @discardableResult
    private func performMutation(
        _ action: KanbanAction,
        operation: @escaping @MainActor () async throws -> Void
    ) async -> Bool {
        guard activeAction == nil else { return false }
        activeAction = action
        defer { activeAction = nil }
        do {
            try await operation()
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            await reconcilePartialFailure(preserving: error.localizedDescription)
            return false
        }
    }

    private func reconcilePartialFailure(preserving message: String) async {
        do {
            _ = try await coordinator.resumePendingTransitions()
            await refresh()
            errorMessage = message
        } catch {
            // Keep the original mutation error; it is more actionable than a recovery failure.
        }
    }

    var selectedCardViewData: KanbanCardViewData? {
        guard let selectedCardID else { return nil }
        return snapshot?.cards.first(where: { $0.id == selectedCardID })
    }

    var selectedLogicalWorkflow: KanbanWorkflow? {
        guard case let .workflow(workflowID)? = selectedCardID else { return nil }
        return lastWorkflows.first(where: { $0.id == workflowID })
    }

    private var selectedCard: KanbanCardViewData? { selectedCardViewData }

    private func shouldPublishDetail(requestID: UUID, taskID: String) -> Bool {
        !Task.isCancelled && detailRequestID == requestID && selectedHermesTaskID == taskID
    }

    private func shouldPublishLog(requestID: UUID, taskID: String) -> Bool {
        !Task.isCancelled && logRequestID == requestID && selectedHermesTaskID == taskID
    }

    private func resolvedSelectedHermesTaskID() -> String? {
        guard let selectedCardID else { return nil }
        switch selectedCardID {
        case let .hermes(taskID):
            return taskID
        case let .workflow(workflowID):
            guard let workflow = lastWorkflows.first(where: { $0.id == workflowID }) else { return nil }
            return representativeHermesTaskID(for: workflow)
        }
    }

    private func updateSelectedHermesTaskID() {
        let taskID = resolvedSelectedHermesTaskID()
        guard taskID != selectedHermesTaskID else { return }
        // Request IDs ensure completions from the old Hermes task cannot overwrite the Inspector.
        detailRequestID = UUID()
        logRequestID = UUID()
        selectedHermesTaskID = taskID
        selectedHermesDetail = nil
        selectedDetail = nil
        selectedLog = nil
    }

    private var lastWorkflows: [KanbanWorkflow] = []

    private func makeCards(
        workflows: [KanbanWorkflow],
        hermesTasks: [HermesKanbanTask]
    ) -> [KanbanCardViewData] {
        lastWorkflows = workflows
        let internalTaskIDs = Set(workflows.flatMap(\.stageReferences).map(\.hermesTaskID))
        let tasksByID = Dictionary(uniqueKeysWithValues: hermesTasks.map { ($0.id, $0) })
        let hermesTaskIDs = Set(tasksByID.keys)
        let workflowCards = workflows.compactMap { workflow -> KanbanCardViewData? in
            let representativeTaskID = representativeHermesTaskID(for: workflow)
            guard (workflow.phase == .triage && representativeTaskID == nil)
                || representativeTaskID.map(hermesTaskIDs.contains) == true
            else {
                return nil
            }
            return workflowCard(workflow, task: representativeTaskID.flatMap { tasksByID[$0] })
        }
        let externalCards = hermesTasks.compactMap { task -> KanbanCardViewData? in
            guard !internalTaskIDs.contains(task.id), let column = KanbanColumn(status: task.status) else {
                return nil
            }
            return KanbanCardViewData(
                id: .hermes(task.id),
                title: task.title,
                column: column,
                priority: KanbanPriority(rawValue: task.priority) ?? .normal,
                displayID: task.id,
                workspacePath: task.workspacePath,
                stageLabel: task.assignee,
                elapsed: elapsed(since: task.startedAtDate),
                createdAt: task.createdAtDate,
                isWorkflowOwned: false,
                availableActions: []
            )
        }
        return sortCards(workflowCards + externalCards)
    }

    private func representativeHermesTaskID(for workflow: KanbanWorkflow) -> String? {
        if let currentStage = workflow.currentStage,
           let reference = workflow.stageReferences.last(where: { $0.stage == currentStage }) {
            return reference.hermesTaskID
        }
        return workflow.stageReferences.last?.hermesTaskID
    }

    private func workflowCard(_ workflow: KanbanWorkflow, task: HermesKanbanTask?) -> KanbanCardViewData {
        let phase = workflow.phase
        let column: KanbanColumn
        var actions: Set<KanbanAvailableAction>
        let stageLabel: String?
        switch phase {
        case .triage:
            column = .triage
            actions = [.start]
            stageLabel = "Triage"
        case .active:
            column = .running
            actions = [.cancel]
            stageLabel = workflow.currentStage?.rawValue.capitalized
        case .approvalRequired:
            column = .ready
            actions = [.approve, .cancel]
            stageLabel = "Approval Required"
        case .blocked:
            column = .blocked
            actions = [.retry]
            stageLabel = workflow.cancellationReason ?? "Blocked"
        case .needsAttention:
            column = .blocked
            actions = workflow.pendingTransition?.kind == .cancel
                ? [.retryCancellationRecovery]
                : []
            stageLabel = "Needs Attention"
        case .done:
            column = .done
            actions = []
            stageLabel = "Done"
        }
        if workflow.pendingTransition?.kind == .cancel, phase != .needsAttention {
            actions = []
        }
        return KanbanCardViewData(
            id: .workflow(workflow.id),
            title: workflow.title,
            column: column,
            priority: workflow.priority,
            displayID: workflow.id.uuidString,
            workspacePath: workflow.workspacePath,
            stageLabel: stageLabel,
            elapsed: elapsed(since: task?.startedAtDate),
            createdAt: workflow.createdAt,
            isWorkflowOwned: true,
            availableActions: actions
        )
    }

    private func sortCards(_ cards: [KanbanCardViewData]) -> [KanbanCardViewData] {
        return cards.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            switch (lhs.createdAt, rhs.createdAt) {
            case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
                return lhsDate < rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            default:
                if lhs.displayID != rhs.displayID { return lhs.displayID < rhs.displayID }
                return cardKindSortOrder(lhs.id) < cardKindSortOrder(rhs.id)
            }
        }
    }

    private func cardKindSortOrder(_ id: KanbanCardID) -> Int {
        switch id {
        case .workflow: 0
        case .hermes: 1
        }
    }

    private func elapsed(since start: Date?) -> TimeInterval? {
        start.map { max(0, Date().timeIntervalSince($0)) }
    }

    private func legacyDetail(from detail: HermesKanbanTaskDetail) -> KanbanTaskDetail {
        let task = detail.task
        let legacyTask = KanbanTask(
            id: task.id,
            title: task.title,
            body: task.body ?? "",
            assignee: task.assignee,
            status: KanbanStatus(rawValue: KanbanColumn(status: task.status)?.rawValue ?? "todo") ?? .todo,
            priority: task.priority,
            createdAt: task.createdAtDate ?? Date(),
            result: task.result
        )
        return KanbanTaskDetail(
            task: legacyTask,
            comments: detail.comments.enumerated().map { index, comment in
                KanbanComment(id: index, author: comment.author, body: comment.body, createdAt: comment.createdAtDate ?? Date())
            },
            events: detail.events.enumerated().map { index, event in
                KanbanEvent(id: index, kind: event.kind, payload: event.payload, createdAt: event.createdAtDate ?? Date())
            }
        )
    }
}
