import Foundation
import XCTest
@testable import OpsHub

final class DevRoomSnapshotDifferTests: XCTestCase {
    func testAddedIssueMarksNewAssignee() {
        let change = DevRoomSnapshotDiffer.diff(
            from: .empty,
            to: snapshot(issueID: 1, employeeID: 10, stage: .todo)
        )
        XCTAssertEqual(change.employeeIDs, [10])
        XCTAssertTrue(change.hasChanges)
    }

    func testStageChangeMarksCurrentAssignee() {
        let old = snapshot(issueID: 1, employeeID: 10, stage: .doing)
        let new = snapshot(issueID: 1, employeeID: 10, stage: .toTest)

        XCTAssertEqual(
            DevRoomSnapshotDiffer.diff(from: old, to: new).employeeIDs,
            [10]
        )
    }

    func testReassignmentMarksOldAndNewEmployees() {
        let old = snapshot(issueID: 1, employeeID: 10, stage: .toTest)
        let new = snapshot(issueID: 1, employeeID: 20, stage: .toTest)

        XCTAssertEqual(
            DevRoomSnapshotDiffer.diff(from: old, to: new).employeeIDs,
            [10, 20]
        )
    }

    func testRemovedIssueMarksPreviousAssignee() {
        let old = snapshot(issueID: 1, employeeID: 10, stage: .passed)

        XCTAssertEqual(
            DevRoomSnapshotDiffer.diff(from: old, to: .empty).employeeIDs,
            [10]
        )
    }

    func testUnchangedSnapshotDoesNotCreateEvent() {
        let value = snapshot(issueID: 1, employeeID: 10, stage: .doing)
        XCTAssertFalse(DevRoomSnapshotDiffer.diff(from: value, to: value).hasChanges)
    }

    func testTitleOnlyChangeDoesNotPulseEmployee() {
        let old = DevRoomSnapshot(issues: [
            1: DevRoomIssueSnapshot(
                assigneeID: 10,
                stage: .doing,
                title: "Old title",
                updatedAt: nil
            )
        ])
        let new = DevRoomSnapshot(issues: [
            1: DevRoomIssueSnapshot(
                assigneeID: 10,
                stage: .doing,
                title: "New title",
                updatedAt: Date()
            )
        ])

        XCTAssertFalse(DevRoomSnapshotDiffer.diff(from: old, to: new).hasChanges)
    }

    private func snapshot(
        issueID: Int,
        employeeID: Int,
        stage: DevRoomWorkflowStage
    ) -> DevRoomSnapshot {
        DevRoomSnapshot(
            issues: [
                issueID: DevRoomIssueSnapshot(
                    assigneeID: employeeID,
                    stage: stage,
                    title: "Issue",
                    updatedAt: nil
                )
            ]
        )
    }
}
