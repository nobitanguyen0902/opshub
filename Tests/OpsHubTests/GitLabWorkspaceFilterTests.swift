import XCTest
@testable import OpsHub

final class GitLabWorkspaceFilterTests: XCTestCase {
    func testMergeRequestSearchIsCaseInsensitiveAndTrimsWhitespace() {
        let items = [
            makeMergeRequest(id: 1, title: "Improve Dashboard", project: "ops/opshub"),
            makeMergeRequest(id: 2, title: "Worker retry", project: "ops/worker")
        ]

        let visible = GitLabWorkspaceFiltering.mergeRequests(
            items,
            scope: .allProjects,
            filter: GitLabWorkspaceFilter(searchText: "  DASHBOARD  ")
        )

        XCTAssertEqual(visible.map(\.id), [1])
    }

    func testProjectScopeFiltersAlreadyLoadedItems() {
        let items = [
            makeMergeRequest(id: 1, title: "One", project: "ops/opshub"),
            makeMergeRequest(id: 2, title: "Two", project: "ops/worker")
        ]
        let scope = GitLabProjectScope.project(
            GitLabProjectSummary(id: 7, nameWithNamespace: "ops/opshub", webURL: nil)
        )

        let visible = GitLabWorkspaceFiltering.mergeRequests(
            items,
            scope: scope,
            filter: GitLabWorkspaceFilter()
        )

        XCTAssertEqual(visible.map(\.id), [1])
    }

    func testIssueWorkflowTabIsAppliedBeforeAdditionalLabelFilter() {
        let issues = [
            makeIssue(id: 1, labels: ["Testing", "backend"]),
            makeIssue(id: 2, labels: ["Testing", "frontend"]),
            makeIssue(id: 3, labels: ["backend"], isWorkflowProject: true)
        ]

        let visible = GitLabWorkspaceFiltering.issues(
            issues,
            scope: .allProjects,
            tab: .testing,
            filter: GitLabWorkspaceFilter(labels: ["backend"])
        )

        XCTAssertEqual(visible.map(\.id), [1])
    }

    func testUpdatedDescendingUsesStableIdentifierTieBreak() {
        let items = [
            makeMergeRequest(id: 1, title: "One", project: "ops/opshub"),
            makeMergeRequest(id: 3, title: "Three", project: "ops/opshub"),
            makeMergeRequest(id: 2, title: "Two", project: "ops/opshub")
        ]

        let sorted = GitLabWorkspaceFiltering.sortMergeRequests(items, by: .updatedDescending)

        XCTAssertEqual(sorted.map(\.id), [3, 2, 1])
    }

    @MainActor
    func testClearFiltersKeepsSelectedScopeAndIssueTab() {
        let viewModel = GitLabDashboardViewModel(service: EmptyGitLabService())
        let scope = GitLabProjectScope.project(
            GitLabProjectSummary(id: 7, nameWithNamespace: "ops/opshub", webURL: nil)
        )
        viewModel.selectedScope = scope
        viewModel.selectedIssueTab = .testing
        viewModel.setFilter(GitLabWorkspaceFilter(searchText: "dashboard"), for: .issues)

        viewModel.clearFilters(for: .issues)

        XCTAssertEqual(viewModel.selectedScope, scope)
        XCTAssertEqual(viewModel.selectedIssueTab, .testing)
        XCTAssertEqual(viewModel.filter(for: .issues), GitLabWorkspaceFilter())
    }

    private func makeMergeRequest(id: Int, title: String, project: String) -> GitLabMergeRequest {
        GitLabMergeRequest(
            id: id,
            title: title,
            project: project,
            status: .opened,
            updatedTime: "Now",
            webURL: nil
        )
    }

    private func makeIssue(
        id: Int,
        labels: [String],
        isWorkflowProject: Bool = true
    ) -> GitLabIssue {
        GitLabIssue(
            id: id,
            title: "Issue \(id)",
            project: "ops/opshub",
            priority: .medium,
            labels: labels,
            isWorkflowProject: isWorkflowProject,
            updatedTime: "Now",
            webURL: nil
        )
    }
}

private struct EmptyGitLabService: GitLabServicing {
    func mergeRequests() async throws -> [GitLabMergeRequest] { [] }
    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }
}
