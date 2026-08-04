import Foundation

enum HermesKanbanStatus: String, Codable, Sendable {
    case triage, todo, scheduled, ready, running, review, blocked, done, archived
}

enum KanbanColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case triage, todo, ready, running, blocked, done
    var id: Self { self }

    init?(status: HermesKanbanStatus) {
        switch status {
        case .triage: self = .triage
        case .todo, .scheduled: self = .todo
        case .ready: self = .ready
        case .running, .review: self = .running
        case .blocked: self = .blocked
        case .done: self = .done
        case .archived: return nil
        }
    }
}

enum KanbanPriority: Int, CaseIterable, Codable, Sendable {
    case low = 0, normal = 1, high = 2, urgent = 3
    var hermesValue: Int { rawValue }
    var title: String { String(describing: self).capitalized }
}

enum KanbanCardID: Hashable, Sendable {
    case workflow(UUID)
    case hermes(String)
}

enum KanbanAvailableAction: Hashable, Sendable {
    case start, approve, cancel, retry, retryCancellationRecovery
}

enum KanbanAction: Hashable, Sendable {
    case createDraft, start, approve, cancel, retry, retryCancellationRecovery
}

struct KanbanCardViewData: Identifiable, Equatable, Sendable {
    let id: KanbanCardID
    let title: String
    let column: KanbanColumn
    let priority: KanbanPriority
    let displayID: String
    let workspacePath: String?
    let stageLabel: String?
    let elapsed: TimeInterval?
    let createdAt: Date?
    let isWorkflowOwned: Bool
    let availableActions: Set<KanbanAvailableAction>

    init(
        id: KanbanCardID,
        title: String,
        column: KanbanColumn,
        priority: KanbanPriority,
        displayID: String,
        workspacePath: String?,
        stageLabel: String?,
        elapsed: TimeInterval?,
        createdAt: Date? = nil,
        isWorkflowOwned: Bool,
        availableActions: Set<KanbanAvailableAction>
    ) {
        self.id = id
        self.title = title
        self.column = column
        self.priority = priority
        self.displayID = displayID
        self.workspacePath = workspacePath
        self.stageLabel = stageLabel
        self.elapsed = elapsed
        self.createdAt = createdAt
        self.isWorkflowOwned = isWorkflowOwned
        self.availableActions = availableActions
    }

    var workspaceName: String? {
        workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

enum KanbanStatus: String, CaseIterable, Identifiable, Hashable { case triage, todo, ready, running, blocked, done; var id: Self { self }; var title: String { rawValue.capitalized } }
struct KanbanTask: Identifiable, Hashable { let id: String; let title: String; let body: String; let assignee: String?; let status: KanbanStatus; let priority: Int; let createdAt: Date; let result: String? }
struct KanbanComment: Identifiable, Hashable { let id: Int; let author: String; let body: String; let createdAt: Date }
struct KanbanEvent: Identifiable, Hashable { let id: Int; let kind: String; let payload: String?; let createdAt: Date }
struct KanbanTaskDetail: Identifiable, Hashable { let task: KanbanTask; let comments: [KanbanComment]; let events: [KanbanEvent]; var id: String { task.id } }
struct KanbanBoardSnapshot: Equatable, Sendable {
    let cards: [KanbanCardViewData]
    let loadedAt: Date

    init(cards: [KanbanCardViewData], loadedAt: Date) {
        self.cards = cards
        self.loadedAt = loadedAt
    }

    // Compatibility projection for callers that still consume the legacy card model.
    init(tasks: [KanbanTask], loadedAt: Date) {
        cards = tasks.map { task in
            KanbanCardViewData(
                id: .hermes(task.id),
                title: task.title,
                column: KanbanColumn(status: HermesKanbanStatus(rawValue: task.status.rawValue) ?? .todo) ?? .todo,
                priority: KanbanPriority(rawValue: task.priority) ?? .normal,
                displayID: task.id,
                workspacePath: nil,
                stageLabel: task.assignee,
                elapsed: nil,
                createdAt: task.createdAt,
                isWorkflowOwned: false,
                availableActions: []
            )
        }
        self.loadedAt = loadedAt
    }

    var tasks: [KanbanTask] {
        cards.map { card in
            KanbanTask(
                id: card.displayID,
                title: card.title,
                body: "",
                assignee: card.stageLabel,
                status: KanbanStatus(rawValue: card.column.rawValue) ?? .todo,
                priority: card.priority.rawValue,
                createdAt: loadedAt.addingTimeInterval(-(card.elapsed ?? 0)),
                result: nil
            )
        }
    }
}
