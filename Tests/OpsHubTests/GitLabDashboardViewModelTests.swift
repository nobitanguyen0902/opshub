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
            ["Merge Requests", "Reviews", "Issues", "Notifications", "Pipelines"]
        )
        XCTAssertEqual(viewModel.statistics.map(\.number), ["1", "1", "1", "1", "1"])
        XCTAssertEqual(viewModel.statistics.map { $0.webURL?.absoluteString }, [
            "https://gitlab.example.com/dashboard/merge_requests?scope=assigned_to_me&state=opened",
            "https://gitlab.example.com/dashboard/merge_requests?scope=reviews_for_me&state=opened",
            "https://gitlab.example.com/dashboard/issues?scope=assigned_to_me&state=opened",
            "https://gitlab.example.com/dashboard/todos",
            "https://gitlab.example.com/-/pipelines"
        ])
        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.mergeReviews.map(\.id), [102])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertEqual(viewModel.notifications.map(\.id), [303])
        XCTAssertEqual(viewModel.pipelines.map(\.id), [404])
        XCTAssertEqual(
            viewModel.summaryMetrics.map(\.kind),
            [.awaitingReview, .assignedToMe, .failedPipelines, .unreadNotifications]
        )
        XCTAssertEqual(viewModel.summaryMetrics.map(\.value), [1, 1, 0, 1])
        XCTAssertEqual(viewModel.selectedScope, .allProjects)
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

        XCTAssertEqual(viewModel.statistics.map(\.number), ["1", "1", "1", "0", "0"])
        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.mergeReviews.map(\.id), [102])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertTrue(viewModel.notifications.isEmpty)
        XCTAssertTrue(viewModel.pipelines.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.loadWarning, "GitLab request failed with status 403.")
        XCTAssertNotNil(viewModel.lastUpdated)
        XCTAssertEqual(viewModel.loadState(for: .notifications), .failed("GitLab request failed with status 403."))
    }

    @MainActor
    func testFailedRefreshKeepsPreviouslyLoadedSectionAndMarksItStale() async {
        let service = FailAfterFirstGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [501])
        XCTAssertEqual(
            viewModel.loadState(for: .mergeRequests),
            .stale("GitLab request failed with status 503.")
        )
    }

    @MainActor
    func testConcurrentRefreshRequestsOnlyStartOneLoadCycle() async {
        let service = SlowCountingGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)

        let first = Task { await viewModel.refresh() }
        for _ in 0..<100 where viewModel.loadState(for: .mergeRequests) != .initialLoading {
            await Task.yield()
        }
        XCTAssertEqual(viewModel.loadState(for: .mergeRequests), .initialLoading)
        let second = Task { await viewModel.refresh() }
        await first.value
        await second.value

        let calls = await service.callCount()
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testTotalInitialFailureLeavesDashboardEmptyWithoutLastUpdatedTimestamp() async {
        let viewModel = GitLabDashboardViewModel(service: TotalFailingGitLabService())

        await viewModel.refresh()

        XCTAssertTrue(viewModel.isEmpty)
        XCTAssertNil(viewModel.lastUpdated)
        XCTAssertEqual(viewModel.loadWarning, "Some GitLab sections could not be loaded.")
        XCTAssertEqual(
            viewModel.loadState(for: .mergeRequests),
            .failed("GitLab request failed with status 503.")
        )
    }

    @MainActor
    func testSummaryMetricRoutesToItsSectionAndFilter() {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())

        viewModel.activate(.failedPipelines)

        XCTAssertEqual(viewModel.selectedSection, .pipelines)
        XCTAssertEqual(
            viewModel.filter(for: .pipelines).statuses,
            [GitLabPipelineStatus.failed.rawValue]
        )

        viewModel.activate(.assignedToMe)

        XCTAssertEqual(viewModel.selectedSection, .issues)
        XCTAssertEqual(viewModel.selectedIssueTab, .assignedToMe)
    }

    @MainActor
    func testRefreshPreservesNavigationSelectionAndSectionFilters() async {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())
        viewModel.selectedSection = .issues
        viewModel.selectedIssueTab = .productionBug
        viewModel.select(.issue(202))
        viewModel.setFilter(
            GitLabWorkspaceFilter(searchText: "mock", labels: ["Bug Production"]),
            for: .issues
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.selectedSection, .issues)
        XCTAssertEqual(viewModel.selectedIssueTab, .productionBug)
        XCTAssertEqual(viewModel.selection.item, .issue(202))
        XCTAssertEqual(viewModel.filter(for: .issues).searchText, "mock")
        XCTAssertEqual(viewModel.filter(for: .issues).labels, ["Bug Production"])
    }
}

private struct TotalFailingGitLabService: GitLabServicing {
    func dashboardStatistics() async throws -> [GitLabStatistic] { [] }
    func projects() async throws -> [GitLabProjectSummary] { throw GitLabServiceError.requestFailed(503) }
    func mergeRequests() async throws -> [GitLabMergeRequest] { throw GitLabServiceError.requestFailed(503) }
    func mergeReviews() async throws -> [GitLabMergeRequest] { throw GitLabServiceError.requestFailed(503) }
    func issues() async throws -> [GitLabIssue] { throw GitLabServiceError.requestFailed(503) }
    func notifications() async throws -> [GitLabNotification] { throw GitLabServiceError.requestFailed(503) }
    func pipelines() async throws -> [GitLabPipeline] { throw GitLabServiceError.requestFailed(503) }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }
}

private actor FailAfterFirstGitLabService: GitLabServicing {
    private var mergeRequestCalls = 0

    func dashboardStatistics() async throws -> [GitLabStatistic] { [] }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        mergeRequestCalls += 1
        guard mergeRequestCalls == 1 else {
            throw GitLabServiceError.requestFailed(503)
        }
        return [
            GitLabMergeRequest(
                id: 501,
                title: "Keep cached merge request",
                project: "ops/opshub",
                status: .opened,
                updatedTime: "Now",
                webURL: nil
            )
        ]
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }
}

private actor SlowCountingGitLabService: GitLabServicing {
    private(set) var mergeRequestCalls = 0

    func dashboardStatistics() async throws -> [GitLabStatistic] { [] }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        mergeRequestCalls += 1
        try await Task.sleep(for: .milliseconds(50))
        return []
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }

    func callCount() -> Int { mergeRequestCalls }
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

    func mergeReviews() async throws -> [GitLabMergeRequest] {
        [
            GitLabMergeRequest(
                id: 102,
                title: "Review protocol-driven GitLab services",
                project: "opshub",
                status: .reviewing,
                updatedTime: "Now",
                webURL: URL(string: "https://gitlab.example.com/opshub/-/merge_requests/102")
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

    func mergeReviews() async throws -> [GitLabMergeRequest] {
        try await StubGitLabService().mergeReviews()
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
