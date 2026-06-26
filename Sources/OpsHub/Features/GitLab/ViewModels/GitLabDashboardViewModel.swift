import Foundation

/// Coordinates GitLab dashboard loading state and formatted dashboard data.
@MainActor
final class GitLabDashboardViewModel: ObservableObject {
    @Published private(set) var statistics: [GitLabStatistic] = []
    @Published private(set) var mergeRequests: [GitLabMergeRequest] = []
    @Published private(set) var issues: [GitLabIssue] = []
    @Published private(set) var notifications: [GitLabNotification] = []
    @Published private(set) var pipelines: [GitLabPipeline] = []
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
        mergeRequests.isEmpty && issues.isEmpty && notifications.isEmpty && pipelines.isEmpty
    }

    func loadDashboard() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        async let mergeRequestsTask = loadSection { try await self.service.mergeRequests() }
        async let issuesTask = loadSection { try await self.service.issues() }
        async let notificationsTask = loadSection { try await self.service.notifications() }
        async let pipelinesTask = loadSection { try await self.service.pipelines() }

        let mergeRequestsResult = await mergeRequestsTask
        let issuesResult = await issuesTask
        let notificationsResult = await notificationsTask
        let pipelinesResult = await pipelinesTask

        mergeRequests = mergeRequestsResult.value ?? []
        issues = issuesResult.value ?? []
        notifications = notificationsResult.value ?? []
        pipelines = pipelinesResult.value ?? []
        loadWarning = loadWarning(for: [
            mergeRequestsResult.error,
            issuesResult.error,
            notificationsResult.error,
            pipelinesResult.error
        ])
        statistics = makeStatistics(
            mergeRequests: mergeRequests,
            issues: issues,
            notifications: notifications,
            pipelines: pipelines
        )
        lastUpdated = .now
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

    private func makeStatistics(
        mergeRequests: [GitLabMergeRequest],
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
