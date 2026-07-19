import XCTest
@testable import OpsHub

final class GitLabIssueTabTests: XCTestCase {
    func testAssignedToMeTabIncludesEveryLoadedIssue() {
        XCTAssertTrue(GitLabIssueTab.assignedToMe.includes(makeIssue(labels: [], isAssignedToMe: true)))
        XCTAssertFalse(GitLabIssueTab.assignedToMe.includes(makeIssue(labels: [], isAssignedToMe: false)))
    }

    func testDoingTabIncludesWorkflowProjectIssueWithDoingLabel() {
        XCTAssertTrue(GitLabIssueTab.doing.includes(makeIssue(labels: ["Doing"])))
        XCTAssertFalse(GitLabIssueTab.doing.includes(makeIssue(labels: ["Testing"])))
    }

    func testDoingTabLabelMatchingIsCaseInsensitiveAndTrimsWhitespace() {
        XCTAssertTrue(GitLabIssueTab.doing.includes(makeIssue(labels: [" DOING "])))
    }

    func testDoingTabExcludesIssuesFromOtherProjects() {
        let issue = makeIssue(labels: ["Doing"], isWorkflowProject: false)

        XCTAssertFalse(GitLabIssueTab.doing.includes(issue))
    }

    func testDoingTabAppearsImmediatelyAfterAssignedToMe() {
        XCTAssertEqual(
            GitLabIssueTab.allCases.prefix(2).map(\.rawValue),
            ["Assign me", "Doing"]
        )
    }

    func testTestingTabIncludesTestingOrToTestLabels() {
        XCTAssertTrue(GitLabIssueTab.testing.includes(makeIssue(labels: ["Testing"])))
        XCTAssertTrue(GitLabIssueTab.testing.includes(makeIssue(labels: ["ToTest"])))
        XCTAssertFalse(GitLabIssueTab.testing.includes(makeIssue(labels: ["Test"])))
        XCTAssertFalse(GitLabIssueTab.testing.includes(makeIssue(labels: ["Passed"])))
    }

    func testTestingTabUsesCanonicalTitle() {
        XCTAssertEqual(GitLabIssueTab.testing.rawValue, "Testing")
    }

    func testPassedTabRequiresPassedAndToProductionLabels() {
        XCTAssertTrue(GitLabIssueTab.passed.includes(makeIssue(labels: ["Passed", "ToProduction"])))
        XCTAssertFalse(GitLabIssueTab.passed.includes(makeIssue(labels: ["Passed"])))
    }

    func testBuildTabRequiresPassedToProductionAndMergedLabels() {
        XCTAssertTrue(GitLabIssueTab.build.includes(makeIssue(labels: ["Passed", "ToProduction", "Merged"])))
        XCTAssertFalse(GitLabIssueTab.build.includes(makeIssue(labels: ["Passed", "ToProduction"])))
    }

    func testProductionBugTabRequiresBugProductionLabel() {
        XCTAssertTrue(GitLabIssueTab.productionBug.includes(makeIssue(labels: ["Bug Production"])))
        XCTAssertFalse(GitLabIssueTab.productionBug.includes(makeIssue(labels: ["Bug"])))
    }

    func testLabelMatchingIsCaseInsensitiveAndTrimsWhitespace() {
        let issue = makeIssue(labels: [" passed ", "TOPRODUCTION", "Merged"])

        XCTAssertTrue(GitLabIssueTab.passed.includes(issue))
        XCTAssertTrue(GitLabIssueTab.build.includes(issue))
    }

    func testWorkflowTabsExcludeIssuesFromOtherProjects() {
        let issue = makeIssue(labels: ["Testing"], isWorkflowProject: false)

        XCTAssertFalse(GitLabIssueTab.testing.includes(issue))
    }

    private func makeIssue(
        labels: [String],
        isAssignedToMe: Bool = false,
        isWorkflowProject: Bool = true
    ) -> GitLabIssue {
        GitLabIssue(
            id: 1,
            title: "Issue",
            project: "OpsHub",
            priority: .low,
            labels: labels,
            isAssignedToMe: isAssignedToMe,
            isWorkflowProject: isWorkflowProject,
            updatedTime: "Now",
            webURL: nil
        )
    }
}
