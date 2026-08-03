import XCTest
import SQLite3
@testable import OpsHub

final class KanbanSQLiteReaderTests: XCTestCase {
    func testDefaultDatabaseURLUsesCurrentHomeDirectory() {
        let expected = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes", isDirectory: true)
            .appendingPathComponent("kanban.db", isDirectory: false)

        XCTAssertEqual(KanbanSQLiteReader.defaultDatabaseURL(), expected)
        XCTAssertFalse(KanbanSQLiteReader.defaultDatabaseURL().path.hasPrefix("~"))
    }

    func testReportsOpenFailureForNonDatabasePath() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-directory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertThrowsError(try KanbanSQLiteReader(url: directory).loadBoard()) { error in
            guard case let .open(message) = error as? KanbanReadError else {
                return XCTFail("Expected an open error, got \(error)")
            }
            XCTAssertFalse(message.isEmpty)
        }
    }

    func testLoadsWALDatabaseWhenSidecarFilesDoNotExist() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-wal-\(UUID().uuidString).db")
        let walURL = URL(fileURLWithPath: url.path + "-wal")
        let shmURL = URL(fileURLWithPath: url.path + "-shm")
        defer {
            try? FileManager.default.removeItem(at: url)
            walURL.withUnsafeFileSystemRepresentation { path in
                if let path { _ = unlink(path) }
            }
            shmURL.withUnsafeFileSystemRepresentation { path in
                if let path { _ = unlink(path) }
            }
        }

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nil, nil, nil), SQLITE_OK)
        let sql = "CREATE TABLE tasks (id TEXT, title TEXT, body TEXT, assignee TEXT, status TEXT, priority INTEGER, created_at REAL, result TEXT); INSERT INTO tasks VALUES ('wal-task','WAL Task','','','todo',1,1.0,NULL);"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_close(db), SQLITE_OK)

        shmURL.withUnsafeFileSystemRepresentation { path in
            if let path { _ = unlink(path) }
        }
        walURL.withUnsafeFileSystemRepresentation { path in
            if let path { _ = unlink(path) }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))

        let snapshot = try KanbanSQLiteReader(url: url).loadBoard()
        XCTAssertEqual(snapshot.tasks.map(\.id), ["wal-task"])
    }

    func testLoadsTasksInPriorityOrder() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kanban-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = "CREATE TABLE tasks (id TEXT, title TEXT, body TEXT, assignee TEXT, status TEXT, priority INTEGER, created_at REAL, result TEXT); INSERT INTO tasks VALUES ('a','A','','','todo',1,1.0,NULL); INSERT INTO tasks VALUES ('b','B','','','done',3,2.0,NULL);"
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        let snapshot = try KanbanSQLiteReader(url: url).loadBoard()
        XCTAssertEqual(snapshot.tasks.map(\.id), ["b", "a"])
        XCTAssertEqual(snapshot.tasks[0].status, .done)
    }

    func testRejectsIncompatibleSchema() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("kanban-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE tasks (id TEXT);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try KanbanSQLiteReader(url: url).loadBoard()) { error in
            XCTAssertEqual(error as? KanbanReadError, .schema)
        }
    }
}

@MainActor
final class KanbanViewModelTests: XCTestCase {
    func testRefreshMapsTasksAndClearsPreviousError() async {
        let task = KanbanTask(id: "1", title: "Task", body: "", assignee: nil, status: .running, priority: 1, createdAt: Date(), result: nil)
        let model = KanbanViewModel(reader: StubKanbanReader(snapshot: KanbanBoardSnapshot(tasks: [task], loadedAt: Date())))
        await model.refresh()
        XCTAssertEqual(model.snapshot?.tasks.first?.status, .running)
        XCTAssertNil(model.errorMessage)
    }

    func testRefreshExposesReaderErrorAndEmptySnapshot() async {
        let model = KanbanViewModel(reader: StubKanbanReader(error: KanbanReadError.query("boom")))
        await model.refresh()
        XCTAssertNil(model.snapshot)
        XCTAssertEqual(model.errorMessage, "Unable to read Kanban database: boom")
    }
}

private struct StubKanbanReader: KanbanDatabaseReading {
    let snapshot: KanbanBoardSnapshot?
    let error: Error?
    init(snapshot: KanbanBoardSnapshot) { self.snapshot = snapshot; self.error = nil }
    init(error: Error) { self.snapshot = nil; self.error = error }
    func loadBoard() throws -> KanbanBoardSnapshot { if let error { throw error }; return snapshot! }
    func loadTaskDetail(taskID: String) throws -> KanbanTaskDetail { fatalError("unused") }
}

extension KanbanReadError: Equatable {
    public static func == (lhs: KanbanReadError, rhs: KanbanReadError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }
}
