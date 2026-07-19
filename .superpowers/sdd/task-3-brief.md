### Task 3: Snapshot diff và animation event domain

**Files:**
- Create: Sources/OpsHub/Features/DevRoom/Models/DevRoomSnapshotDiffer.swift
- Test: Tests/OpsHubTests/DevRoomSnapshotDifferTests.swift

**Interfaces:**
- Consumes: DevRoomData, DevRoomIssue.
- Produces:
  - DevRoomIssueSnapshot
  - DevRoomSnapshot
  - DevRoomChangeSet
  - DevRoomSnapshotDiffer.diff(from:to:) -> DevRoomChangeSet

- [ ] **Step 1: Viết failing diff tests**

Tạo Tests/OpsHubTests/DevRoomSnapshotDifferTests.swift:

~~~swift
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
~~~

- [ ] **Step 2: Chạy tests và xác nhận fail**

Run:

~~~bash
swift test --filter DevRoomSnapshotDifferTests
~~~

Expected: build FAIL vì snapshot types chưa tồn tại.

- [ ] **Step 3: Implement pure snapshot differ**

Tạo Sources/OpsHub/Features/DevRoom/Models/DevRoomSnapshotDiffer.swift:

~~~swift
import Foundation

struct DevRoomIssueSnapshot: Equatable, Sendable {
    let assigneeID: Int
    let stage: DevRoomWorkflowStage
    let title: String
    let updatedAt: Date?
}

struct DevRoomSnapshot: Equatable, Sendable {
    let issues: [Int: DevRoomIssueSnapshot]

    static let empty = DevRoomSnapshot(issues: [:])

    init(issues: [Int: DevRoomIssueSnapshot]) {
        self.issues = issues
    }

    init(data: DevRoomData) {
        issues = Dictionary(uniqueKeysWithValues: data.issues.map {
            (
                $0.id,
                DevRoomIssueSnapshot(
                    assigneeID: $0.assignee.id,
                    stage: $0.stage,
                    title: $0.title,
                    updatedAt: $0.updatedAt
                )
            )
        })
    }
}

struct DevRoomChangeSet: Equatable, Sendable {
    let employeeIDs: Set<Int>
    var hasChanges: Bool { employeeIDs.isEmpty == false }
}

enum DevRoomSnapshotDiffer {
    static func diff(from old: DevRoomSnapshot, to new: DevRoomSnapshot) -> DevRoomChangeSet {
        var employeeIDs: Set<Int> = []
        let issueIDs = Set(old.issues.keys).union(new.issues.keys)

        for issueID in issueIDs {
            let oldIssue = old.issues[issueID]
            let newIssue = new.issues[issueID]
            let ownershipOrStageChanged = oldIssue?.assigneeID != newIssue?.assigneeID
                || oldIssue?.stage != newIssue?.stage
            guard ownershipOrStageChanged else { continue }
            if let oldIssue { employeeIDs.insert(oldIssue.assigneeID) }
            if let newIssue { employeeIDs.insert(newIssue.assigneeID) }
        }

        return DevRoomChangeSet(employeeIDs: employeeIDs)
    }
}
~~~

- [ ] **Step 4: Chạy targeted tests**

Run:

~~~bash
swift test --filter DevRoomSnapshotDifferTests
~~~

Expected: PASS.

- [ ] **Step 5: Commit snapshot diff**

~~~bash
git add Sources/OpsHub/Features/DevRoom/Models/DevRoomSnapshotDiffer.swift Tests/OpsHubTests/DevRoomSnapshotDifferTests.swift
git commit -m "feat(dev-room): detect task snapshot changes"
~~~

---

