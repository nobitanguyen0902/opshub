import XCTest
@testable import OpsHub

final class GitLabWorkItemPresentationTests: XCTestCase {
    func testMergeRequestPresentationKeepsIdentityParticipantAndTimestamp() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let mergeRequest = GitLabMergeRequest(
            id: 1_042,
            iid: 42,
            title: "Improve dashboard",
            project: "ops/opshub",
            status: .reviewing,
            authorName: "Octo Cat",
            authorAvatarURL: URL(string: "https://gitlab.example.com/avatar.png"),
            updatedAt: date,
            updatedTime: "2 hours ago",
            webURL: URL(string: "https://gitlab.example.com/ops/opshub/-/merge_requests/42")
        )

        let item = GitLabWorkItemPresentation(mergeRequest: mergeRequest, context: .mergeRequest)

        XCTAssertEqual(item.id, .mergeRequest(1_042))
        XCTAssertEqual(item.reference, "!42")
        XCTAssertEqual(item.status.title, "Reviewing")
        XCTAssertEqual(item.participants.map(\.name), ["Octo Cat"])
        XCTAssertEqual(item.updatedAt, date)
        XCTAssertTrue(item.accessibilitySummary.contains("Merge request !42"))
    }

    func testReviewPresentationUsesSeparateIdentifierSpace() {
        let mergeRequest = GitLabMergeRequest(
            id: 1_042,
            iid: 42,
            title: "Review dashboard",
            project: "ops/opshub",
            status: .reviewing,
            updatedTime: "Now",
            webURL: nil
        )

        let item = GitLabWorkItemPresentation(mergeRequest: mergeRequest, context: .review)

        XCTAssertEqual(item.id, .review(1_042))
        XCTAssertNil(item.webURL)
    }

    func testIssuePresentationPreservesLabelsAndMissingURL() {
        let issue = GitLabIssue(
            id: 2_077,
            iid: 77,
            title: "Production bug",
            project: "ops/opshub",
            priority: .urgent,
            labels: ["Bug Production"],
            updatedTime: "Now",
            webURL: nil
        )

        let item = GitLabWorkItemPresentation(issue: issue)

        XCTAssertEqual(item.id, .issue(2_077))
        XCTAssertEqual(item.labels.map(\.name), ["Bug Production"])
        XCTAssertEqual(item.priority, .critical)
        XCTAssertNil(item.webURL)
    }

    func testFailedPipelinePresentationIsCriticalAndKeepsURL() {
        let pipeline = GitLabPipeline(
            id: 9001,
            project: "ops/opshub",
            branch: "main",
            status: .failed,
            updatedTime: "Now",
            webURL: URL(string: "https://gitlab.example.com/ops/opshub/-/pipelines/9001")
        )

        let item = GitLabWorkItemPresentation(pipeline: pipeline)

        XCTAssertEqual(item.id, .pipeline(9001))
        XCTAssertEqual(item.status.semantic, .error)
        XCTAssertEqual(item.priority, .critical)
        XCTAssertNotNil(item.webURL)
    }

    func testNotificationPresentationUsesAuthorAndTargetURL() {
        let notification = GitLabNotification(
            id: 3,
            title: "Review requested",
            project: "ops/opshub",
            kind: .reviewRequested,
            authorName: "Reviewer",
            updatedTime: "Now",
            webURL: URL(string: "https://gitlab.example.com/todos/3")
        )

        let item = GitLabWorkItemPresentation(notification: notification)

        XCTAssertEqual(item.id, .notification(3))
        XCTAssertEqual(item.participants.map(\.name), ["Reviewer"])
        XCTAssertEqual(item.status.title, "Review requested")
        XCTAssertNotNil(item.webURL)
    }
}
