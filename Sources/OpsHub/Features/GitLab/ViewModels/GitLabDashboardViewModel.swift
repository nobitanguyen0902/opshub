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

    private let service: any GitLabServicing

    init(service: any GitLabServicing = GitLabService()) {
        self.service = service
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

        do {
            async let mergeRequestsTask = service.mergeRequests()
            async let issuesTask = service.issues()
            async let notificationsTask = service.notifications()
            async let pipelinesTask = service.pipelines()

            let loadedMergeRequests = try await mergeRequestsTask
            let loadedIssues = try await issuesTask
            let loadedNotifications = try await notificationsTask
            let loadedPipelines = try await pipelinesTask

            mergeRequests = loadedMergeRequests
            issues = loadedIssues
            notifications = loadedNotifications
            pipelines = loadedPipelines
            statistics = makeStatistics(
                mergeRequests: loadedMergeRequests,
                issues: loadedIssues,
                notifications: loadedNotifications,
                pipelines: loadedPipelines
            )
            lastUpdated = .now
        } catch {
            statistics = []
            mergeRequests = []
            issues = []
            notifications = []
            pipelines = []
        }
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
                subtitle: "Assigned open merge requests"
            ),
            GitLabStatistic(
                icon: "exclamationmark.circle",
                title: "Issues",
                number: "\(issues.count)",
                subtitle: "Assigned open issues"
            ),
            GitLabStatistic(
                icon: "bell.badge",
                title: "Notifications",
                number: "\(notifications.count)",
                subtitle: "\(reviewRequests) review requests"
            ),
            GitLabStatistic(
                icon: "play.circle",
                title: "Pipelines",
                number: "\(pipelines.count)",
                subtitle: "\(failedPipelines) failed pipelines"
            )
        ]
    }
}
