import XCTest
@testable import OpsHub

final class KanbanDomainTests: XCTestCase {
    func testHermesStatusesProjectIntoSixColumns() {
        XCTAssertEqual(KanbanColumn(status: .triage), .triage)
        XCTAssertEqual(KanbanColumn(status: .todo), .todo)
        XCTAssertEqual(KanbanColumn(status: .scheduled), .todo)
        XCTAssertEqual(KanbanColumn(status: .ready), .ready)
        XCTAssertEqual(KanbanColumn(status: .running), .running)
        XCTAssertEqual(KanbanColumn(status: .review), .running)
        XCTAssertEqual(KanbanColumn(status: .blocked), .blocked)
        XCTAssertEqual(KanbanColumn(status: .done), .done)
        XCTAssertNil(KanbanColumn(status: .archived))
    }

    func testPriorityMapsToHermesInteger() {
        XCTAssertEqual(KanbanPriority.allCases.map(\.hermesValue), [0, 1, 2, 3])
        XCTAssertEqual(KanbanPriority.normal.title, "Normal")
    }

    func testReviewerHandoffRequiresFindingsArray() throws {
        let valid = #"{"schemaVersion":1,"outcome":"approved","summary":"LGTM","findings":[]}"#
        let handoff = try JSONDecoder().decode(ReviewerHandoff.self, from: Data(valid.utf8))
        XCTAssertEqual(handoff.outcome, .approved)

        let invalid = #"{"schemaVersion":1,"outcome":"approved","summary":"LGTM"}"#
        XCTAssertThrowsError(try JSONDecoder().decode(ReviewerHandoff.self, from: Data(invalid.utf8)))
    }

    func testStageHandoffsRejectUnsupportedSchemaVersion() {
        let payload = #"{"schemaVersion":2,"outcome":"ready","summary":"Ready","risks":[]}"#

        XCTAssertThrowsError(try JSONDecoder().decode(ArchitectHandoff.self, from: Data(payload.utf8)))
    }

    func testHermesTaskKeepsEpochTimestampAndExposesPresentationDate() {
        let task = HermesKanbanTask(
            id: "task-1",
            title: "Task",
            body: nil,
            assignee: nil,
            status: .todo,
            priority: 1,
            tenant: nil,
            workspaceKind: "repository",
            workspacePath: nil,
            branchName: nil,
            projectID: nil,
            createdBy: nil,
            createdAt: 1_700_000_000,
            startedAt: nil,
            completedAt: nil,
            result: nil
        )

        XCTAssertEqual(task.createdAt, 1_700_000_000)
        XCTAssertEqual(task.createdAtDate, Date(timeIntervalSince1970: 1_700_000_000))
    }
}
