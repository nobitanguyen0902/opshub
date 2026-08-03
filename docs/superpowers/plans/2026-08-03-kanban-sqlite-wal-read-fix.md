# Kanban SQLite WAL Read Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho phép OpsHub đọc `~/.hermes/kanban.db` ở journal mode WAL khi các file sidecar chưa tồn tại.

**Architecture:** Giữ nguyên `KanbanSQLiteReader` và toàn bộ truy vấn chỉ đọc hiện có. Chỉ thay cờ kết nối SQLite sang `SQLITE_OPEN_READWRITE` để SQLite có thể khởi tạo WAL/SHM, với regression test tái hiện database WAL đã đóng sạch và không còn sidecar.

**Tech Stack:** Swift 6, XCTest, SQLite3, Swift Package Manager

## Global Constraints

- Không thay đổi đường dẫn database, schema, model, UI hoặc thông báo lỗi.
- `KanbanSQLiteReader` chỉ thực thi `SELECT` và `PRAGMA table_info`; không thêm câu lệnh ghi dữ liệu.
- Không dùng `immutable=1` vì Hermes có thể cập nhật database đồng thời.
- Không commit, push hoặc mở PR nếu người dùng chưa yêu cầu rõ.

---

### Task 1: Regression coverage và sửa cờ mở SQLite

**Files:**
- Modify: `Tests/OpsHubTests/KanbanTests.swift`
- Modify: `Sources/OpsHub/Features/Kanban/Services/KanbanSQLiteReader.swift`

**Interfaces:**
- Consumes: `KanbanSQLiteReader.init(url:)` và `KanbanSQLiteReader.loadBoard()` hiện có.
- Produces: Hành vi `loadBoard()` đọc được database WAL không có `-wal`/`-shm`; không thay đổi signature công khai.

- [ ] **Step 1: Viết regression test tạo database WAL không còn sidecar**

Thêm test sau vào `KanbanSQLiteReaderTests`:

```swift
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
```

- [ ] **Step 2: Chạy regression test để xác nhận lỗi hiện tại**

Run:

```bash
swift test --filter KanbanSQLiteReaderTests/testLoadsWALDatabaseWhenSidecarFilesDoNotExist
```

Expected: FAIL tại `loadBoard()` với `Unable to read Kanban database: unable to open database file`.

- [ ] **Step 3: Thay đổi tối thiểu cờ mở database**

Trong `KanbanSQLiteReader.open()`, thay:

```swift
let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil)
```

bằng:

```swift
let rc = sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil)
```

Không thay đổi các truy vấn SQL hoặc error mapping.

- [ ] **Step 4: Chạy test Kanban hẹp**

Run:

```bash
swift test --filter KanbanSQLiteReaderTests
swift test --filter KanbanViewModelTests
```

Expected: Toàn bộ test Kanban đạt, bao gồm regression test mới và test lỗi mở directory hiện có.

- [ ] **Step 5: Chạy xác minh repository**

Run:

```bash
swift test
swift build
git diff --check
git status --short
```

Expected: Build và test đạt; diff chỉ gồm spec, plan, regression test và thay đổi một cờ SQLite; `.worktrees/` hiện có vẫn không bị chỉnh sửa.

- [ ] **Step 6: Rà soát diff và bàn giao, không commit**

Xác nhận không có câu lệnh ghi Kanban mới, không thay đổi contract, và báo lại các lệnh kiểm thử đã chạy cùng mọi giới hạn còn lại.
