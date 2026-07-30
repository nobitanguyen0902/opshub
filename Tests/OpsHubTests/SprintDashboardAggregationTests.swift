import Foundation
import XCTest
@testable import OpsHub

final class SprintDashboardAggregationTests: XCTestCase {
    private var vietnamCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    func testCurrentMilestoneUsesInclusiveVietnamDateBoundary() {
        let milestone = makeMilestone(
            id: 31,
            start: "2026-07-29T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )

        XCTAssertEqual(
            SprintDashboardAggregator.currentMilestone(
                from: [milestone],
                now: date("2026-08-04T23:59:59+07:00"),
                calendar: vietnamCalendar
            )?.id,
            31
        )
        XCTAssertNil(
            SprintDashboardAggregator.currentMilestone(
                from: [milestone],
                now: date("2026-08-05T00:00:00+07:00"),
                calendar: vietnamCalendar
            )
        )
    }

    func testCurrentMilestoneChoosesLatestStartThenLargestIDWhenRangesOverlap() {
        let older = makeMilestone(
            id: 30,
            start: "2026-07-22T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )
        let newerLowerID = makeMilestone(
            id: 31,
            start: "2026-07-29T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )
        let newerHigherID = makeMilestone(
            id: 32,
            start: "2026-07-29T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )

        XCTAssertEqual(
            SprintDashboardAggregator.currentMilestone(
                from: [newerLowerID, older, newerHigherID],
                now: date("2026-07-30T12:00:00+07:00"),
                calendar: vietnamCalendar
            )?.id,
            32
        )
    }

    func testAggregationCountsReleaseOnlyWithAllThreeNormalizedLabels() {
        let alice = member(id: 1, name: "Alice")
        let issues = [
            issue(
                id: 1,
                labels: [" Passed ", "TOPRODUCTION", "merged"],
                assignee: alice
            ),
            issue(
                id: 2,
                labels: ["Passed", "ToProduction"],
                assignee: alice
            )
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: issues,
            productionBugs: [],
            selectedUserIDs: [alice.id],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.ticketCount, 2)
        XCTAssertEqual(data.releasedCount, 1)
        XCTAssertEqual(data.memberSummaries.first?.ticketCount, 2)
        XCTAssertEqual(data.memberSummaries.first?.releasedCount, 1)
    }

    func testProductionBugCountIgnoresMilestoneAndAssigneeButFiltersLabelAndCreatedAt() {
        let bob = member(id: 2, name: "Bob")
        let bugs = [
            issue(
                id: 10,
                labels: ["Bug Production"],
                assignee: nil,
                createdAt: "2026-07-29T00:00:00+07:00"
            ),
            issue(
                id: 11,
                labels: [" bug production "],
                assignee: bob,
                createdAt: "2026-08-04T23:59:59+07:00"
            ),
            issue(
                id: 12,
                labels: ["Bug"],
                assignee: nil,
                createdAt: "2026-07-30T12:00:00+07:00"
            ),
            issue(
                id: 13,
                labels: ["Bug Production"],
                assignee: nil,
                createdAt: "2026-08-05T00:00:00+07:00"
            ),
            issue(
                id: 14,
                labels: ["Bug Production"],
                assignee: nil,
                createdAt: nil
            )
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: [],
            productionBugs: bugs,
            selectedUserIDs: [],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.productionBugCount, 2)
        XCTAssertEqual(data.productionBugPreview.map(\.id), [11, 10])
    }

    func testMemberBreakdownUsesSelectedCurrentAssigneeAndKeepsUnassignedLast() {
        let alice = member(id: 1, name: "Alice")
        let bob = member(id: 2, name: "Bob")
        let issues = [
            issue(id: 1, labels: [], assignee: alice),
            issue(
                id: 2,
                labels: ["Passed", "ToProduction", "Merged"],
                assignee: alice
            ),
            issue(id: 3, labels: [], assignee: bob),
            issue(id: 4, labels: [], assignee: nil)
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: issues,
            productionBugs: [],
            selectedUserIDs: [alice.id],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.ticketCount, 4)
        XCTAssertEqual(data.releasedCount, 1)
        XCTAssertEqual(data.memberSummaries.map(\.member?.id), [alice.id, nil])
        XCTAssertEqual(data.memberSummaries.map(\.ticketCount), [2, 1])
        XCTAssertEqual(data.memberSummaries.map(\.releasedCount), [1, 0])
        XCTAssertEqual(data.memberSummaries[0].issues.map(\.id), [2, 1])
        XCTAssertEqual(data.memberSummaries[1].issues.map(\.id), [4])
    }

    func testMemberSummaryIssuesSortByNewestUpdateThenDescendingGlobalID() {
        let alice = member(id: 1, name: "Alice")
        let issues = [
            issue(id: 1, labels: [], assignee: alice, updatedAt: "2026-07-29T08:00:00+07:00"),
            issue(id: 2, labels: [], assignee: alice, updatedAt: "2026-07-30T08:00:00+07:00"),
            issue(id: 3, labels: [], assignee: alice, updatedAt: "2026-07-30T08:00:00+07:00")
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: issues,
            productionBugs: [],
            selectedUserIDs: [alice.id],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.memberSummaries.first?.issues.map(\.id), [3, 2, 1])
    }

    func testDuplicateGlobalIssueIDCountsOnceUsingMostRecentlyUpdatedIssue() {
        let alice = member(id: 1, name: "Alice")
        let bob = member(id: 2, name: "Bob")
        let issues = [
            issue(
                id: 1,
                title: "Older",
                labels: [],
                assignee: alice,
                updatedAt: "2026-07-29T08:00:00+07:00"
            ),
            issue(
                id: 1,
                title: "Current",
                labels: ["Passed", "ToProduction", "Merged"],
                assignee: bob,
                updatedAt: "2026-07-30T08:00:00+07:00"
            )
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: issues,
            productionBugs: [],
            selectedUserIDs: [alice.id, bob.id],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.ticketCount, 1)
        XCTAssertEqual(data.releasedCount, 1)
        XCTAssertEqual(data.memberSummaries.map(\.member?.id), [bob.id])
        XCTAssertEqual(data.memberSummaries.first?.issues.map(\.title), ["Current"])
    }

    func testDuplicateWithMatchingTimestampKeepsFirstResponseItem() {
        let alice = member(id: 1, name: "Alice")
        let bob = member(id: 2, name: "Bob")
        let timestamp = "2026-07-30T08:00:00+07:00"
        let issues = [
            issue(
                id: 1,
                labels: [],
                assignee: alice,
                updatedAt: timestamp
            ),
            issue(
                id: 1,
                labels: ["Passed", "ToProduction", "Merged"],
                assignee: bob,
                updatedAt: timestamp
            )
        ]

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: issues,
            productionBugs: [],
            selectedUserIDs: [alice.id, bob.id],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.releasedCount, 0)
        XCTAssertEqual(data.memberSummaries.map(\.member?.id), [alice.id])
    }

    func testProductionBugPreviewKeepsFiveNewestItems() {
        let timestamps = [
            "2026-07-29T12:00:00+07:00",
            "2026-07-30T12:00:00+07:00",
            "2026-07-31T12:00:00+07:00",
            "2026-08-01T12:00:00+07:00",
            "2026-08-02T12:00:00+07:00",
            "2026-08-03T12:00:00+07:00",
            "2026-08-04T12:00:00+07:00"
        ]
        let bugs = timestamps.enumerated().map { index, timestamp in
            issue(
                id: index + 1,
                labels: ["Bug Production"],
                assignee: nil,
                createdAt: timestamp
            )
        }

        let data = SprintDashboardAggregator.makeData(
            milestone: currentMilestone,
            sprintIssues: [],
            productionBugs: bugs,
            selectedUserIDs: [],
            calendar: vietnamCalendar
        )

        XCTAssertEqual(data.productionBugCount, 7)
        XCTAssertEqual(data.productionBugPreview.map(\.id), [7, 6, 5, 4, 3])
    }

    private var currentMilestone: SprintMilestone {
        makeMilestone(
            id: 31,
            start: "2026-07-29T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )
    }

    private func makeMilestone(
        id: Int,
        start: String,
        due: String
    ) -> SprintMilestone {
        SprintMilestone(
            id: id,
            title: "Sprint \(id)",
            startDate: date(start),
            dueDate: date(due)
        )
    }

    private func member(id: Int, name: String) -> SprintDashboardMember {
        SprintDashboardMember(
            id: id,
            name: name,
            username: name.lowercased(),
            avatarURL: nil
        )
    }

    private func issue(
        id: Int,
        title: String = "Issue",
        labels: [String],
        assignee: SprintDashboardMember?,
        createdAt: String? = "2026-07-30T12:00:00+07:00",
        updatedAt: String? = nil
    ) -> SprintDashboardIssue {
        SprintDashboardIssue(
            id: id,
            iid: id,
            title: title,
            project: "social/socom-issues",
            labels: labels,
            assignee: assignee,
            createdAt: createdAt.map(date),
            updatedAt: updatedAt.map(date),
            webURL: URL(string: "https://gitlab.example.com/issues/\(id)")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
