import Foundation

enum KanbanStatus: String, CaseIterable, Identifiable, Hashable { case triage, todo, ready, running, blocked, done; var id: Self { self }; var title: String { rawValue.capitalized } }
struct KanbanTask: Identifiable, Hashable { let id: String; let title: String; let body: String; let assignee: String?; let status: KanbanStatus; let priority: Int; let createdAt: Date; let result: String? }
struct KanbanComment: Identifiable, Hashable { let id: Int; let author: String; let body: String; let createdAt: Date }
struct KanbanEvent: Identifiable, Hashable { let id: Int; let kind: String; let payload: String?; let createdAt: Date }
struct KanbanTaskDetail: Identifiable, Hashable { let task: KanbanTask; let comments: [KanbanComment]; let events: [KanbanEvent]; var id: String { task.id } }
struct KanbanBoardSnapshot { let tasks: [KanbanTask]; let loadedAt: Date }
enum KanbanReadError: LocalizedError { case missing, open(String), schema, query(String); var errorDescription: String? { switch self { case .missing: "Kanban database was not found at ~/.hermes/kanban.db"; case .open(let s): "Unable to open Kanban database: \(s)"; case .schema: "Kanban database schema is incompatible"; case .query(let s): "Unable to read Kanban database: \(s)" } } }
