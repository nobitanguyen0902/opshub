import XCTest
@testable import OpsHub

final class GitLabWorkspaceStateTests: XCTestCase {
    func testWorkspaceSectionsHaveStableApprovedOrder() {
        XCTAssertEqual(
            GitLabWorkspaceSection.allCases,
            [.overview, .mergeRequests, .reviews, .issues, .pipelines, .notifications]
        )
        XCTAssertEqual(
            GitLabWorkspaceSection.allCases.map(\.title),
            ["Overview", "Merge Requests", "Reviews", "Issues", "Pipelines", "Notifications"]
        )
    }

    func testWorkspaceSectionIdentityDoesNotDependOnTitle() {
        XCTAssertEqual(GitLabWorkspaceSection.reviews.id, .reviews)
        XCTAssertEqual(GitLabWorkspaceSection.reviews.rawValue, "reviews")
    }

    func testCountKeepsTotalActionableUnreadAndVisibleSeparate() {
        let count = GitLabCount(total: 62, actionable: 12, unread: 20, visible: 5)

        XCTAssertEqual(count.total, 62)
        XCTAssertEqual(count.actionable, 12)
        XCTAssertEqual(count.unread, 20)
        XCTAssertEqual(count.visible, 5)
    }

    func testActionPrioritySortsMostUrgentFirst() {
        let priorities: [GitLabActionPriority] = [.normal, .critical, .low, .high]

        XCTAssertEqual(priorities.sorted(), [.critical, .high, .normal, .low])
    }

    func testWorkspaceSelectionDefaultsToOverviewWithoutSelectedItem() {
        let selection = GitLabWorkspaceSelection()

        XCTAssertEqual(selection.section, .overview)
        XCTAssertNil(selection.item)
    }

    func testAdaptiveLayoutUsesApprovedWidthBoundaries() {
        XCTAssertEqual(GitLabWorkspaceLayoutMode(width: 719), .narrow)
        XCTAssertEqual(GitLabWorkspaceLayoutMode(width: 839), .narrow)
        XCTAssertEqual(GitLabWorkspaceLayoutMode(width: 840), .compact)
        XCTAssertEqual(GitLabWorkspaceLayoutMode(width: 1_179), .compact)
        XCTAssertEqual(GitLabWorkspaceLayoutMode(width: 1_180), .wide)
    }

    func testNavigationBadgeHidesZeroAndCapsLargeValues() {
        XCTAssertNil(GitLabNavigationBadgeText.value(for: 0))
        XCTAssertEqual(GitLabNavigationBadgeText.value(for: 99), "99")
        XCTAssertEqual(GitLabNavigationBadgeText.value(for: 100), "99+")
    }
}
