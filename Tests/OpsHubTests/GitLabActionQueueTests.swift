import XCTest
@testable import OpsHub

final class GitLabActionQueueTests: XCTestCase {
    func testQueueDeduplicatesAndSortsByPriorityThenRecency() {
        let older = Date(timeIntervalSince1970: 100)
        let newer = Date(timeIntervalSince1970: 200)
        let duplicate = GitLabNotification(
            id: 1, title: "Mention", project: "ops/app", kind: .mentioned,
            updatedAt: older, updatedTime: "Earlier"
        )
        let refreshedDuplicate = GitLabNotification(
            id: 1, title: "Mention updated", project: "ops/app", kind: .mentioned,
            updatedAt: newer, updatedTime: "Now"
        )
        let failed = GitLabPipeline(
            id: 2, project: "ops/app", branch: "main", status: .failed,
            updatedAt: older, updatedTime: "Earlier"
        )

        let result = GitLabActionQueueBuilder.build(
            reviews: [], issues: [], pipelines: [failed],
            notifications: [duplicate, refreshedDuplicate], scope: .allProjects
        )

        XCTAssertEqual(result.map(\.id), [.pipeline(2), .notification(1)])
        XCTAssertEqual(result.last?.title, "Mention updated")
    }

    func testQueueIncludesOnlyAssignedIssuesAndSelectedProject() {
        let assigned = GitLabIssue(
            id: 1, title: "Assigned", project: "ops/app", priority: .high,
            isAssignedToMe: true, updatedTime: "Now", webURL: nil
        )
        let unassigned = GitLabIssue(
            id: 2, title: "Other", project: "ops/app", priority: .urgent,
            isAssignedToMe: false, updatedTime: "Now", webURL: nil
        )
        let scope = GitLabProjectScope.project(
            GitLabProjectSummary(id: 1, nameWithNamespace: "ops/app", webURL: nil)
        )

        let result = GitLabActionQueueBuilder.build(
            reviews: [], issues: [assigned, unassigned], pipelines: [], notifications: [], scope: scope
        )

        XCTAssertEqual(result.map(\.id), [.issue(1)])
    }

    func testQueueTransformsRepresentativeLargeDatasetWithoutDroppingItems() {
        let notifications = (1...2_000).map { id in
            GitLabNotification(
                id: id,
                title: "Notification \(id)",
                project: "ops/app",
                kind: id.isMultiple(of: 2) ? .mentioned : .reviewRequested,
                updatedAt: Date(timeIntervalSince1970: TimeInterval(id)),
                updatedTime: "Recently"
            )
        }

        let result = GitLabActionQueueBuilder.build(
            reviews: [], issues: [], pipelines: [], notifications: notifications, scope: .allProjects
        )

        XCTAssertEqual(result.count, 2_000)
        XCTAssertEqual(result.first?.priority, .high)
        XCTAssertEqual(result.first?.id, .notification(1_999))
    }

    func testQueueDeduplicatesNotificationTargetingTheSameMergeRequest() {
        let review = GitLabMergeRequest(
            id: 1_001, iid: 7, title: "Review me", project: "ops/app",
            status: .reviewing, updatedTime: "Now", webURL: nil
        )
        let notification = GitLabNotification(
            id: 99, title: "Review requested", project: "ops/app", kind: .reviewRequested,
            updatedTime: "Now",
            targetResourceKey: GitLabResourceKey(kind: .mergeRequest, project: "ops/app", id: 1_001)
        )

        let result = GitLabActionQueueBuilder.build(
            reviews: [review], issues: [], pipelines: [], notifications: [notification], scope: .allProjects
        )

        XCTAssertEqual(result.map(\.id), [.review(1_001)])
    }
}
