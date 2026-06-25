import Foundation

@MainActor
final class GitLabDashboardViewModel: ObservableObject {
    @Published private(set) var mergeRequests: [GitLabMergeRequest] = []
    @Published private(set) var issues: [GitLabIssue] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?

    var statistics: [GitLabStatistic] {
        [
            GitLabStatistic(
                icon: "arrow.triangle.merge",
                title: "Merge Requests",
                number: "\(mergeRequests.count)",
                subtitle: "\(mergeRequests.count { $0.status == .reviewing }) waiting for review"
            ),
            GitLabStatistic(
                icon: "exclamationmark.circle",
                title: "Issues",
                number: "\(issues.count)",
                subtitle: "\(issues.count { $0.priority == .urgent || $0.priority == .high }) high priority"
            ),
            GitLabStatistic(
                icon: "checkmark.seal",
                title: "Approved",
                number: "\(mergeRequests.count { $0.status == .approved })",
                subtitle: "Ready to merge"
            ),
            GitLabStatistic(
                icon: "bell.badge",
                title: "Attention",
                number: "\(attentionCount)",
                subtitle: "Needs follow-up"
            )
        ]
    }

    var isEmpty: Bool {
        mergeRequests.isEmpty && issues.isEmpty
    }

    func loadDashboard() async {
        await refresh()
    }

    func refresh() async {
        isLoading = true

        do {
            try await Task.sleep(for: .milliseconds(350))
        } catch {}

        mergeRequests = GitLabMocks.mergeRequests
        issues = GitLabMocks.issues
        lastUpdated = .now
        isLoading = false
    }

    private var attentionCount: Int {
        mergeRequests.count { $0.status == .reviewing || $0.status == .opened }
            + issues.count { $0.priority == .urgent || $0.priority == .high }
    }
}

struct GitLabStatistic: Identifiable, Hashable {
    let icon: String
    let title: String
    let number: String
    let subtitle: String

    var id: String { title }
}
