import XCTest
@testable import OpsHub

final class GitLabDashboardViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsDashboardDataFromInjectedService() async {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())

        await viewModel.refresh()

        XCTAssertEqual(viewModel.statistics.map(\.title), ["Attention"])
        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertEqual(viewModel.notifications.map(\.id), [303])
        XCTAssertEqual(viewModel.pipelines.map(\.id), [404])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.lastUpdated)
    }
}

private struct StubGitLabService: GitLabServicing {
    func dashboardStatistics() async throws -> [GitLabStatistic] {
        [
            GitLabStatistic(
                icon: "bell.badge",
                title: "Attention",
                number: "1",
                subtitle: "Injected service data"
            )
        ]
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        [
            GitLabMergeRequest(
                id: 101,
                title: "Use protocol-driven GitLab services",
                project: "opshub",
                status: .reviewing,
                updatedTime: "Now"
            )
        ]
    }

    func issues() async throws -> [GitLabIssue] {
        [
            GitLabIssue(
                id: 202,
                title: "Add GitLab mock issue source",
                project: "opshub",
                priority: .high,
                updatedTime: "Now"
            )
        ]
    }

    func notifications() async throws -> [GitLabNotification] {
        [
            GitLabNotification(
                id: 303,
                title: "Review requested",
                project: "opshub",
                kind: .reviewRequested,
                updatedTime: "Now"
            )
        ]
    }

    func pipelines() async throws -> [GitLabPipeline] {
        [
            GitLabPipeline(
                id: 404,
                project: "opshub",
                branch: "main",
                status: .passed,
                updatedTime: "Now"
            )
        ]
    }
}
