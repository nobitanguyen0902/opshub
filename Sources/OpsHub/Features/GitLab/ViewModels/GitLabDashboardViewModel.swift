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

    init(service: any GitLabServicing = GitLabMockService()) {
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
            async let loadedStatistics = service.dashboardStatistics()
            async let loadedMergeRequests = service.mergeRequests()
            async let loadedIssues = service.issues()
            async let loadedNotifications = service.notifications()
            async let loadedPipelines = service.pipelines()

            statistics = try await loadedStatistics
            mergeRequests = try await loadedMergeRequests
            issues = try await loadedIssues
            notifications = try await loadedNotifications
            pipelines = try await loadedPipelines
            lastUpdated = .now
        } catch {
            statistics = []
            mergeRequests = []
            issues = []
            notifications = []
            pipelines = []
        }
    }
}
