import XCTest
@testable import OpsHub

final class GitLabDashboardViewModelTests: XCTestCase {
    @MainActor
    func testRefreshLoadsDashboardDataFromInjectedService() async {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())

        await viewModel.refresh()

        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.mergeReviews.map(\.id), [102])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertEqual(viewModel.pipelines.map(\.id), [404])
        XCTAssertEqual(
            viewModel.summaryMetrics.map(\.kind),
            [.awaitingReview, .mergeRequests, .assignedToMe, .failedPipelines]
        )
        XCTAssertEqual(viewModel.summaryMetrics.map(\.value), [1, 1, 1, 0])
        XCTAssertFalse(viewModel.actionQueue.contains { $0.id == .notification(303) })
        XCTAssertEqual(viewModel.selectedScope, .allProjects)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    @MainActor
    func testRefreshKeepsLoadedSectionsWhenOneSectionFails() async {
        let viewModel = GitLabDashboardViewModel(service: PartiallyFailingGitLabService())

        await viewModel.refresh()

        XCTAssertEqual(viewModel.mergeRequests.map(\.id), [101])
        XCTAssertEqual(viewModel.mergeReviews.map(\.id), [102])
        XCTAssertEqual(viewModel.issues.map(\.id), [202])
        XCTAssertTrue(viewModel.pipelines.isEmpty)
        XCTAssertFalse(viewModel.isEmpty)
        XCTAssertEqual(viewModel.loadWarning, "GitLab request failed with status 403.")
        XCTAssertNotNil(viewModel.lastUpdated)
        XCTAssertEqual(
            viewModel.loadState(for: .pipelines),
            .failed("GitLab request failed with status 403.")
        )
        XCTAssertEqual(
            viewModel.overviewLoadState,
            .stale("GitLab request failed with status 403.")
        )
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
    func testLoadDashboardReusesCurrentScopeUntilManualRefresh() async {
        let service = SlowCountingGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)

        await viewModel.loadDashboard()
        await viewModel.loadDashboard()

        let callsAfterReopen = await service.callCount()
        XCTAssertEqual(callsAfterReopen, 1)

        await viewModel.refresh()

        let callsAfterManualRefresh = await service.callCount()
        XCTAssertEqual(callsAfterManualRefresh, 2)
    }

    @MainActor
    func testLoadDashboardFetchesWhenScopeChanges() async {
        let service = ScopeCountingGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)
        let project = GitLabProjectSummary(id: 9, nameWithNamespace: "group/project", webURL: nil)

        await viewModel.loadDashboard()
        viewModel.selectedScope = .project(project)
        await viewModel.loadDashboard()

        let loadedScopes = await service.loadedScopes()
        XCTAssertEqual(loadedScopes, ["All projects", "group/project"])
    }

    @MainActor
    func testLoadDashboardRetriesAfterTotalInitialFailure() async {
        let service = CountingFailingGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)

        await viewModel.loadDashboard()
        await viewModel.loadDashboard()

        let calls = await service.callCount()
        XCTAssertEqual(calls, 2)
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
        XCTAssertEqual(viewModel.overviewLoadState, .failed("Some GitLab sections could not be loaded."))
    }

    @MainActor
    func testSummaryMetricRoutesToItsSectionAndFilter() {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())

        viewModel.activate(.mergeRequests)

        XCTAssertEqual(viewModel.selectedSection, .mergeRequests)

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
    func testOverviewSearchFiltersActionQueueAndPreviews() async {
        let viewModel = GitLabDashboardViewModel(service: StubGitLabService())
        await viewModel.refresh()

        viewModel.selectedSection = .overview
        viewModel.searchText = "protocol-driven"

        XCTAssertEqual(viewModel.actionQueue.map(\.id), [.review(102)])
        XCTAssertEqual(viewModel.mergeRequestPreview.map(\.id), [.mergeRequest(101)])
        XCTAssertTrue(viewModel.pipelinePreview.isEmpty)
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

    @MainActor
    func testRefreshDoesNotApplyResultsFromAPreviouslySelectedScope() async {
        let service = ScopeAwareGitLabService()
        let viewModel = GitLabDashboardViewModel(service: service)
        let projectA = GitLabProjectSummary(id: 1, nameWithNamespace: "group/a", webURL: nil)
        let projectB = GitLabProjectSummary(id: 2, nameWithNamespace: "group/b", webURL: nil)

        viewModel.selectedScope = .project(projectA)
        let first = Task { await viewModel.refresh() }
        await Task.yield()
        viewModel.selectedScope = .project(projectB)
        let second = Task { await viewModel.refresh() }
        await first.value
        await second.value

        XCTAssertEqual(viewModel.selectedScope, .project(projectB))
        XCTAssertEqual(viewModel.mergeRequests.map(\.project), ["group/b"])
    }
}

private struct ScopeAwareGitLabService: GitLabServicing {
    func mergeRequests() async throws -> [GitLabMergeRequest] { [] }
    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        if scope.title == "group/a" { try await Task.sleep(for: .milliseconds(30)) }
        return [GitLabMergeRequest(
            id: scope.title == "group/a" ? 1 : 2,
            title: scope.title,
            project: scope.title,
            status: .opened,
            updatedTime: "Now",
            webURL: nil
        )]
    }
    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }
}

private struct TotalFailingGitLabService: GitLabServicing {
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

private actor ScopeCountingGitLabService: GitLabServicing {
    private var scopes: [String] = []

    func mergeRequests() async throws -> [GitLabMergeRequest] { [] }

    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        scopes.append(scope.title)
        return []
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }

    func loadedScopes() -> [String] { scopes }
}

private actor CountingFailingGitLabService: GitLabServicing {
    private var calls = 0

    func projects() async throws -> [GitLabProjectSummary] {
        throw GitLabServiceError.requestFailed(503)
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        calls += 1
        throw GitLabServiceError.requestFailed(503)
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] {
        throw GitLabServiceError.requestFailed(503)
    }

    func issues() async throws -> [GitLabIssue] {
        throw GitLabServiceError.requestFailed(503)
    }

    func notifications() async throws -> [GitLabNotification] {
        throw GitLabServiceError.requestFailed(503)
    }

    func pipelines() async throws -> [GitLabPipeline] {
        throw GitLabServiceError.requestFailed(503)
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult { .connected }

    func callCount() -> Int { calls }
}

private struct StubGitLabService: GitLabServicing {
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
        []
    }

    func pipelines() async throws -> [GitLabPipeline] {
        throw GitLabServiceError.requestFailed(403)
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }
}
