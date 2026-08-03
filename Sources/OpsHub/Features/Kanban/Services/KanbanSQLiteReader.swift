import Foundation
import os
import SQLite3

protocol KanbanDatabaseReading: Sendable { func loadBoard() throws -> KanbanBoardSnapshot; func loadTaskDetail(taskID: String) throws -> KanbanTaskDetail }

struct KanbanSQLiteReader: KanbanDatabaseReading {
    private static let logger = Logger(subsystem: "com.opshub.app", category: "KanbanSQLiteReader")

    let url: URL
    init(url: URL = Self.defaultDatabaseURL()) { self.url = url }

    static func defaultDatabaseURL(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("kanban.db", isDirectory: false)
    }
    func loadBoard() throws -> KanbanBoardSnapshot {
        let db = try open(); defer { sqlite3_close(db) }
        try validate(db)
        let sql = "SELECT id,title,body,assignee,status,priority,created_at,result FROM tasks ORDER BY priority DESC,created_at ASC,id ASC"
        let rows = try query(db, sql: sql)
        return KanbanBoardSnapshot(tasks: rows.compactMap(task), loadedAt: Date())
    }
    func loadTaskDetail(taskID: String) throws -> KanbanTaskDetail {
        let db = try open(); defer { sqlite3_close(db) }; try validate(db)
        let taskRows = try query(db, sql: "SELECT id,title,body,assignee,status,priority,created_at,result FROM tasks WHERE id = ?", binds: [taskID])
        guard let task = taskRows.compactMap(task).first else { throw KanbanReadError.query("Task not found") }
        let comments = try query(db, sql: "SELECT id,author,body,created_at FROM task_comments WHERE task_id = ? ORDER BY created_at ASC,id ASC", binds: [taskID]).compactMap { r in Int(r[0]) .map { KanbanComment(id:$0,author:r[1],body:r[2],createdAt:Date(timeIntervalSince1970: Double(r[3]) ?? 0)) } }
        let events = try query(db, sql: "SELECT id,kind,payload,created_at FROM task_events WHERE task_id = ? ORDER BY created_at ASC,id ASC", binds: [taskID]).compactMap { r in Int(r[0]).map { KanbanEvent(id:$0,kind:r[1],payload:r[2].isEmpty ? nil : r[2],createdAt:Date(timeIntervalSince1970:Double(r[3]) ?? 0)) } }
        return KanbanTaskDetail(task: task, comments: comments, events: events)
    }
    private func open() throws -> OpaquePointer {
        let exists = FileManager.default.fileExists(atPath: url.path)
        Self.logger.debug("Resolving Kanban database path: \(self.url.path, privacy: .public), fileExists=\(exists, privacy: .public)")
        guard exists else { throw KanbanReadError.missing }

        var db: OpaquePointer?
        let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
        let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? String(cString: sqlite3_errstr(rc))
        if rc != SQLITE_OK {
            Self.logger.error("sqlite3_open_v2 failed: code=\(rc, privacy: .public), message=\(errorMessage, privacy: .public)")
        }
        guard rc == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            throw KanbanReadError.open(errorMessage)
        }
        return db
    }
    private func validate(_ db: OpaquePointer) throws { let rows = try query(db, sql: "PRAGMA table_info(tasks)"); let names = Set(rows.map{$0[1]}); guard Set(["id","title","status","priority","created_at"]).isSubset(of:names) else { throw KanbanReadError.schema } }
    private func query(_ db: OpaquePointer, sql: String, binds: [String] = []) throws -> [[String]] { var stmt: OpaquePointer?; guard sqlite3_prepare_v2(db,sql,-1,&stmt,nil) == SQLITE_OK else { throw KanbanReadError.query(String(cString:sqlite3_errmsg(db))) }; defer { sqlite3_finalize(stmt) }; for (i,v) in binds.enumerated() { sqlite3_bind_text(stmt,Int32(i+1),v,-1,unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }; var out:[[String]]=[]
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                out.append((0..<sqlite3_column_count(stmt)).map { i in sqlite3_column_text(stmt,i).map(String.init(cString:)) ?? "" })
            } else if rc == SQLITE_DONE {
                return out
            } else {
                throw KanbanReadError.query(String(cString: sqlite3_errmsg(db)))
            }
        }
    }
    private func task(_ r:[String]) -> KanbanTask? { guard r.count >= 8, let s=KanbanStatus(rawValue:r[4]), let p=Int(r[5]), let t=Double(r[6]) else { return nil }; return KanbanTask(id:r[0],title:r[1],body:r[2],assignee:r[3].isEmpty ? nil:r[3],status:s,priority:p,createdAt:Date(timeIntervalSince1970:t),result:r[7].isEmpty ? nil:r[7]) }
}

extension KanbanSQLiteReader: @unchecked Sendable {}
extension Optional where Wrapped == String { var isEmpty: Bool { self?.isEmpty ?? true } }
