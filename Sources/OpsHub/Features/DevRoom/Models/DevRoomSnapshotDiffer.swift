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
