import XCTest
@testable import OpsHub

final class SprintDashboardMemberInspectorTests: XCTestCase {
    func testMilestoneLinkRequiresGitLabWebURL() {
        let linked = SprintMilestone(
            id: 31,
            title: "Sprint 31",
            startDate: .distantPast,
            dueDate: .distantFuture,
            webURL: URL(string: "https://gitlab.example.com/milestones/31")
        )
        let unavailable = SprintMilestone(
            id: 30,
            title: "Sprint 30",
            startDate: .distantPast,
            dueDate: .distantFuture,
            webURL: nil
        )

        XCTAssertTrue(SprintDashboardMilestonePresentation.canOpen(linked))
        XCTAssertFalse(SprintDashboardMilestonePresentation.canOpen(unavailable))
    }

    func testInspectorUsesPreferredWidthWhenSpaceAllows() {
        let placement = SprintDashboardInspectorLayout.placement(for: 900)
        XCTAssertEqual(placement.width, 460)
        XCTAssertEqual(placement.trailingInset, 0)
    }

    func testInspectorKeepsHorizontalInsetsInNarrowSpace() {
        let placement = SprintDashboardInspectorLayout.placement(for: 400)
        XCTAssertEqual(placement.width, 368)
        XCTAssertEqual(placement.trailingInset, 16)
    }

    func testWorkflowLabelUsesHighestProgressKnownLabel() {
        let issue = SprintDashboardIssue(
            id: 1,
            iid: 10,
            title: "Issue",
            project: "social/socom-issues",
            labels: ["Doing", "Passed", "ToProduction"],
            assignee: nil,
            createdAt: nil,
            updatedAt: nil,
            webURL: nil
        )

        XCTAssertEqual(
            SprintDashboardIssuePresentation.workflowLabel(for: issue),
            "ToProduction"
        )
        XCTAssertFalse(SprintDashboardIssuePresentation.canOpen(issue))
    }

    @MainActor
    func testInspectorCloseInvokesAction() {
        var closeCount = 0
        let inspector = SprintDashboardMemberInspector(
            summary: SprintDashboardMemberSummary(member: nil, issues: []),
            onClose: { closeCount += 1 }
        )

        inspector.close()

        XCTAssertEqual(closeCount, 1)
    }

    @MainActor
    func testInspectorBackdropDismissInvokesAction() {
        var dismissCount = 0
        let backdrop = SprintDashboardInspectorBackdrop {
            dismissCount += 1
        }

        backdrop.dismiss()

        XCTAssertEqual(dismissCount, 1)
    }

    func testFocusRouterReturnsToMemberAfterInspectorCloses() {
        XCTAssertEqual(
            SprintDashboardInspectorFocusRouter.target(
                previousSummaryID: "member:41",
                selectedSummaryID: nil,
                displayedSummaryIDs: ["member:41", "unassigned"]
            ),
            "member:41"
        )
    }

    func testFocusRouterDoesNotReturnToRemovedMember() {
        XCTAssertNil(
            SprintDashboardInspectorFocusRouter.target(
                previousSummaryID: "member:41",
                selectedSummaryID: nil,
                displayedSummaryIDs: ["member:52"]
            )
        )
    }
}
