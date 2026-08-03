import XCTest
@testable import OpsHub

final class KanbanWorkflowStoreTests: XCTestCase {
    func testStoreRoundTripsWorkflowAtomically() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-store-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let store = FileKanbanWorkflowStore(url: url)
        let workflow = makeTriageWorkflow()

        try await store.save([workflow])

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [workflow])
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testStoreReturnsEmptyWorkflowsWhenFileIsMissing() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-missing-\(UUID().uuidString)/workflows.json")
        let store = FileKanbanWorkflowStore(url: url)

        let loaded = try await store.load()
        XCTAssertEqual(loaded, [])
    }

    func testStoreRejectsUnsupportedSchema() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-schema-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let store = FileKanbanWorkflowStore(url: url)
        let data = #"[{"schemaVersion":99}]"#.data(using: .utf8)!
        try data.write(to: url)

        do {
            _ = try await store.load()
            XCTFail("Expected unsupported schema")
        } catch {
            XCTAssertEqual(error as? KanbanWorkflowStoreError, .unsupportedSchema(99))
        }
    }

    func testStoreRejectsCorruptJSON() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-corrupt-\(UUID().uuidString)/workflows.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not JSON".utf8).write(to: url)
        let store = FileKanbanWorkflowStore(url: url)

        do {
            _ = try await store.load()
            XCTFail("Expected corrupt data")
        } catch {
            XCTAssertEqual(error as? KanbanWorkflowStoreError, .corruptData)
        }
    }

    func testFailedSaveLeavesPreviouslyValidFileReadable() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kanban-save-failure-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("workflows.json")
        let fileManager = FileManager.default
        defer { try? fileManager.removeItem(at: directory) }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileKanbanWorkflowStore(url: url)
        let original = makeTriageWorkflow()
        try await store.save([original])
        try fileManager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }

        do {
            try await store.save([makeTriageWorkflow(title: "Updated")])
            XCTFail("Expected save failure")
        } catch {
            let loaded = try await store.load()
            XCTAssertEqual(loaded, [original])
        }
    }

    private func makeTriageWorkflow(title: String = "Task") -> KanbanWorkflow {
        KanbanWorkflow(
            schemaVersion: 1,
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            title: title,
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
}
