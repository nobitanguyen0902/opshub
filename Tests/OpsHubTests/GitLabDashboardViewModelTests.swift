import XCTest
@testable import OpsHub

final class GitLabDashboardViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsDashboardDataFromInjectedService() async {
        let viewModel = GitLabDashboardViewModel(
            service: StubGitLabService(),
            gitLabBaseURL: URL(string: "https://gitlab.example.com")
        )

        await viewModel.refresh()

        XCTAssertEqual(
            viewModel.statistics.map(\.title),
            ["Merge Requests", "Issues", "Notifications", "Pipelines"]
        )
        XCTAssertEqual(viewModel.statistics.map(\.number), ["1", "1", "1", "1"])
        XCTAssertEqual(viewModel.statistics.map { $0.webURL?.absoluteString }, [
            "https://gitlab.example.com/dashboard/merge_requests?scope=assigned_to_me&state=opened",
            "https://gitlab.example.com/dashboard/issues?scope=assigned_to_me&state=opened",
            "https://gitlab.example.com/dashboard/todos",
            "https://gitlab.example.com/-/pipelines"
        ])
        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertEqual(viewModel.notifications.map(\.id), [303])
        XCTAssertEqual(viewModel.pipelines.map(\.id), [404])
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    @MainActor
    func testRefreshKeepsLoadedSectionsWhenOneSectionFails() async {
        let viewModel = GitLabDashboardViewModel(
            service: PartiallyFailingGitLabService(),
            gitLabBaseURL: URL(string: "https://gitlab.example.com")
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.statistics.map(\.number), ["1", "1", "0", "0"])
        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertTrue(viewModel.notifications.isEmpty)
        XCTAssertTrue(viewModel.pipelines.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.loadWarning, "GitLab request failed with status 403.")
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
                subtitle: "Injected service data",
                webURL: nil
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
                updatedTime: "Now",
                webURL: URL(string: "https://gitlab.example.com/opshub/-/merge_requests/101")
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
                updatedTime: "Now",
                webURL: URL(string: "https://gitlab.example.com/opshub/-/issues/202")
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

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }
}

private struct PartiallyFailingGitLabService: GitLabServicing {
    func dashboardStatistics() async throws -> [GitLabStatistic] {
        []
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        try await StubGitLabService().mergeRequests()
    }

    func issues() async throws -> [GitLabIssue] {
        try await StubGitLabService().issues()
    }

    func notifications() async throws -> [GitLabNotification] {
        throw GitLabServiceError.requestFailed(403)
    }

    func pipelines() async throws -> [GitLabPipeline] {
        []
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }
}
