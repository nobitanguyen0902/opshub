import Foundation

/// Coordinates GitLab dashboard loading state and formatted dashboard data.
@MainActor
final class GitLabDashboardViewModel: ObservableObject {
    @Published var selection = GitLabWorkspaceSelection()
    @Published var selectedScope: GitLabProjectScope = .allProjects
    @Published var selectedIssueTab: GitLabIssueTab = .assignedToMe
    @Published private var sectionFilters: [GitLabWorkspaceSection: GitLabWorkspaceFilter] = [:]
    @Published private(set) var projects: [GitLabProjectSummary] = []
    @Published private(set) var statistics: [GitLabStatistic] = []
    @Published private(set) var mergeRequests: [GitLabMergeRequest] = []
    @Published private(set) var mergeReviews: [GitLabMergeRequest] = []
    @Published private(set) var issues: [GitLabIssue] = []
    @Published private(set) var notifications: [GitLabNotification] = []
    @Published private(set) var pipelines: [GitLabPipeline] = []
    @Published private(set) var sectionStates: [GitLabWorkspaceSection: GitLabSectionLoadState] = [:]
    @Published private(set) var sectionUpdatedAt: [GitLabWorkspaceSection: Date] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var loadWarning: String?

    private let service: any GitLabServicing
    private let gitLabBaseURL: URL?

    init(
        service: any GitLabServicing = GitLabService(),
        gitLabBaseURL: URL? = nil
    ) {
        self.service = service
        self.gitLabBaseURL = gitLabBaseURL
    }

    var isEmpty: Bool {
        mergeRequests.isEmpty && mergeReviews.isEmpty && issues.isEmpty && notifications.isEmpty && pipelines.isEmpty
    }

    var selectedSection: GitLabWorkspaceSection {
        get { selection.section }
        set { selection.section = newValue }
    }

    var visibleMergeRequests: [GitLabMergeRequest] {
        GitLabWorkspaceFiltering.sortMergeRequests(
            GitLabWorkspaceFiltering.mergeRequests(
                mergeRequests,
                scope: selectedScope,
                filter: filter(for: .mergeRequests)
            ),
            by: .updatedDescending
        )
    }

    var visibleMergeReviews: [GitLabMergeRequest] {
        GitLabWorkspaceFiltering.sortMergeRequests(
            GitLabWorkspaceFiltering.mergeRequests(
                mergeReviews,
                scope: selectedScope,
                filter: filter(for: .reviews)
            ),
            by: .updatedDescending
        )
    }

    var visibleIssues: [GitLabIssue] {
        GitLabWorkspaceFiltering.sortIssues(
            GitLabWorkspaceFiltering.issues(
                issues,
                scope: selectedScope,
                tab: selectedIssueTab,
                filter: filter(for: .issues)
            )
        )
    }

    var visibleNotifications: [GitLabNotification] {
        GitLabWorkspaceFiltering.sortNotifications(
            GitLabWorkspaceFiltering.notifications(
                notifications,
                scope: selectedScope,
                filter: filter(for: .notifications)
            )
        )
    }

    var visiblePipelines: [GitLabPipeline] {
        GitLabWorkspaceFiltering.sortPipelines(
            GitLabWorkspaceFiltering.pipelines(
                pipelines,
                scope: selectedScope,
                filter: filter(for: .pipelines)
            )
        )
    }

    func filter(for section: GitLabWorkspaceSection) -> GitLabWorkspaceFilter {
        sectionFilters[section] ?? GitLabWorkspaceFilter()
    }

    func setFilter(_ filter: GitLabWorkspaceFilter, for section: GitLabWorkspaceSection) {
        sectionFilters[section] = filter
    }

    func clearFilters(for section: GitLabWorkspaceSection) {
        sectionFilters[section] = GitLabWorkspaceFilter()
    }

    func loadState(for section: GitLabWorkspaceSection) -> GitLabSectionLoadState {
        sectionStates[section] ?? .idle
    }

    func select(_ item: GitLabWorkspaceItemID?) {
        selection.item = item
    }

    func loadDashboard() async {
        await refresh()
    }

    func refresh() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }

        beginLoading(.mergeRequests, hasData: mergeRequests.isEmpty == false)
        beginLoading(.reviews, hasData: mergeReviews.isEmpty == false)
        beginLoading(.issues, hasData: issues.isEmpty == false)
        beginLoading(.notifications, hasData: notifications.isEmpty == false)
        beginLoading(.pipelines, hasData: pipelines.isEmpty == false)

        let scope = selectedScope
        async let projectsTask = loadSection { try await self.service.projects() }
        async let mergeRequestsTask = loadSection { try await self.service.mergeRequests(scope: scope) }
        async let mergeReviewsTask = loadSection { try await self.service.mergeReviews(scope: scope) }
        async let issuesTask = loadSection { try await self.service.issues(scope: scope) }
        async let notificationsTask = loadSection { try await self.service.notifications(scope: scope) }
        async let pipelinesTask = loadSection { try await self.service.pipelines(scope: scope) }

        let projectsResult = await projectsTask
        let mergeRequestsResult = await mergeRequestsTask
        let mergeReviewsResult = await mergeReviewsTask
        let issuesResult = await issuesTask
        let notificationsResult = await notificationsTask
        let pipelinesResult = await pipelinesTask

        if let loadedProjects = projectsResult.value {
            projects = loadedProjects
        }
        let mergeRequestsSucceeded = apply(
            mergeRequestsResult,
            section: .mergeRequests,
            hadData: mergeRequests.isEmpty == false
        ) { mergeRequests = $0 }
        let mergeReviewsSucceeded = apply(
            mergeReviewsResult,
            section: .reviews,
            hadData: mergeReviews.isEmpty == false
        ) { mergeReviews = $0 }
        let issuesSucceeded = apply(
            issuesResult,
            section: .issues,
            hadData: issues.isEmpty == false
        ) { issues = $0 }
        let notificationsSucceeded = apply(
            notificationsResult,
            section: .notifications,
            hadData: notifications.isEmpty == false
        ) { notifications = $0 }
        let pipelinesSucceeded = apply(
            pipelinesResult,
            section: .pipelines,
            hadData: pipelines.isEmpty == false
        ) { pipelines = $0 }
        loadWarning = loadWarning(for: [
            projectsResult.error,
            mergeRequestsResult.error,
            mergeReviewsResult.error,
            issuesResult.error,
            notificationsResult.error,
            pipelinesResult.error
        ])
        statistics = makeStatistics(
            mergeRequests: mergeRequests,
            mergeReviews: mergeReviews,
            issues: issues,
            notifications: notifications,
            pipelines: pipelines
        )
        if projectsResult.value != nil
            || mergeRequestsSucceeded
            || mergeReviewsSucceeded
            || issuesSucceeded
            || notificationsSucceeded
            || pipelinesSucceeded {
            lastUpdated = .now
        }
    }

    private func beginLoading(_ section: GitLabWorkspaceSection, hasData: Bool) {
        sectionStates[section] = hasData ? .refreshing : .initialLoading
    }

    @discardableResult
    private func apply<Value: Sendable>(
        _ result: Result<Value, any Error>,
        section: GitLabWorkspaceSection,
        hadData: Bool,
        assign: (Value) -> Void
    ) -> Bool {
        switch result {
        case let .success(value):
            assign(value)
            sectionStates[section] = .loaded
            sectionUpdatedAt[section] = .now
            return true
        case let .failure(error):
            let message = errorMessage(error)
            sectionStates[section] = hadData ? .stale(message) : .failed(message)
            return false
        }
    }

    private func loadSection<Value: Sendable>(
        _ load: @escaping () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await load())
        } catch {
            return .failure(error)
        }
    }

    private func loadWarning(for errors: [Error?]) -> String? {
        let errors = errors.compactMap { $0 }
        guard errors.isEmpty == false else {
            return nil
        }

        if errors.count == 1, let description = (errors.first as? LocalizedError)?.errorDescription {
            return description
        }

        return "Some GitLab sections could not be loaded."
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func makeStatistics(
        mergeRequests: [GitLabMergeRequest],
        mergeReviews: [GitLabMergeRequest],
        issues: [GitLabIssue],
        notifications: [GitLabNotification],
        pipelines: [GitLabPipeline]
    ) -> [GitLabStatistic] {
        let failedPipelines = pipelines.filter { $0.status == .failed }.count
        let reviewRequests = notifications.filter { $0.kind == .reviewRequested }.count

        return [
            GitLabStatistic(
                icon: "arrow.triangle.merge",
                title: "Merge Requests",
                number: "\(mergeRequests.count)",
                subtitle: "Assigned open merge requests",
                webURL: dashboardURL(path: "dashboard/merge_requests", queryItems: [
                    URLQueryItem(name: "scope", value: "assigned_to_me"),
                    URLQueryItem(name: "state", value: "opened")
                ])
            ),
            GitLabStatistic(
                icon: "checkmark.bubble",
                title: "Reviews",
                number: "\(mergeReviews.count)",
                subtitle: "Open merge requests awaiting your review",
                webURL: dashboardURL(path: "dashboard/merge_requests", queryItems: [
                    URLQueryItem(name: "scope", value: "reviews_for_me"),
                    URLQueryItem(name: "state", value: "opened")
                ])
            ),
            GitLabStatistic(
                icon: "exclamationmark.circle",
                title: "Issues",
                number: "\(issues.count)",
                subtitle: "Assigned open issues",
                webURL: dashboardURL(path: "dashboard/issues", queryItems: [
                    URLQueryItem(name: "scope", value: "assigned_to_me"),
                    URLQueryItem(name: "state", value: "opened")
                ])
            ),
            GitLabStatistic(
                icon: "bell.badge",
                title: "Notifications",
                number: "\(notifications.count)",
                subtitle: "\(reviewRequests) review requests",
                webURL: dashboardURL(path: "dashboard/todos")
            ),
            GitLabStatistic(
                icon: "play.circle",
                title: "Pipelines",
                number: "\(pipelines.count)",
                subtitle: "\(failedPipelines) failed pipelines",
                webURL: dashboardURL(path: "-/pipelines")
            )
        ]
    }

    private func dashboardURL(
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL? {
        guard
            let gitLabBaseURL,
            var components = URLComponents(url: gitLabBaseURL, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let dashboardPath = [basePath, path]
            .filter { $0.isEmpty == false }
            .joined(separator: "/")
        components.path = "/\(dashboardPath)"
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url
    }
}

private extension Result {
    var value: Success? {
        if case let .success(value) = self {
            return value
        }

        return nil
    }

    var error: Failure? {
        if case let .failure(error) = self {
            return error
        }

        return nil
    }
}
