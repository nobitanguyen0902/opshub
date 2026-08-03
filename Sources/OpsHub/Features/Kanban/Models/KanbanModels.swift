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

enum KanbanStatus: String, CaseIterable, Identifiable, Hashable { case triage, todo, ready, running, blocked, done; var id: Self { self }; var title: String { rawValue.capitalized } }
struct KanbanTask: Identifiable, Hashable { let id: String; let title: String; let body: String; let assignee: String?; let status: KanbanStatus; let priority: Int; let createdAt: Date; let result: String? }
struct KanbanComment: Identifiable, Hashable { let id: Int; let author: String; let body: String; let createdAt: Date }
struct KanbanEvent: Identifiable, Hashable { let id: Int; let kind: String; let payload: String?; let createdAt: Date }
struct KanbanTaskDetail: Identifiable, Hashable { let task: KanbanTask; let comments: [KanbanComment]; let events: [KanbanEvent]; var id: String { task.id } }
struct KanbanBoardSnapshot { let tasks: [KanbanTask]; let loadedAt: Date }
enum KanbanReadError: LocalizedError {
    case missing
    case open(String)
    case schema
    case query(String)

    var errorDescription: String? {
        switch self {
        case .missing:
            "Kanban database was not found in the Hermes data directory"
        case .open(let message):
            "Unable to open Kanban database: \(message)"
        case .schema:
            "Kanban database schema is incompatible"
        case .query(let message):
            "Unable to read Kanban database: \(message)"
        }
    }
}
