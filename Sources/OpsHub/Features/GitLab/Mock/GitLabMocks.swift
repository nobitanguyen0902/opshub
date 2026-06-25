enum GitLabMocks {
    static let statistics: [GitLabStatistic] = [
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
            icon: "bell.badge",
            title: "Notifications",
            number: "\(notifications.count)",
            subtitle: "\(notifications.count { $0.kind == .mentioned || $0.kind == .reviewRequested }) need attention"
        ),
        GitLabStatistic(
            icon: "checkmark.seal",
            title: "Pipelines",
            number: "\(pipelines.count { $0.status == .passed })/\(pipelines.count)",
            subtitle: "\(pipelines.count { $0.status == .failed }) failed"
        )
    ]

    static let mergeRequests: [GitLabMergeRequest] = [
        GitLabMergeRequest(
            id: 1842,
            title: "Add participant tag sync for inbox updates",
            project: "social-api",
            status: .reviewing,
            updatedTime: "12m ago"
        ),
        GitLabMergeRequest(
            id: 1837,
            title: "Fix retry worker timeout handling",
            project: "harasocial-services",
            status: .opened,
            updatedTime: "46m ago"
        ),
        GitLabMergeRequest(
            id: 1829,
            title: "Update release packaging workflow",
            project: "opshub",
            status: .approved,
            updatedTime: "2h ago"
        ),
        GitLabMergeRequest(
            id: 1818,
            title: "Draft Mongo index migration notes",
            project: "social-api",
            status: .draft,
            updatedTime: "Yesterday"
        )
    ]

    static let issues: [GitLabIssue] = [
        GitLabIssue(
            id: 9281,
            title: "Conversation list skips unread count after reconnect",
            project: "social-api",
            priority: .urgent,
            updatedTime: "8m ago"
        ),
        GitLabIssue(
            id: 9274,
            title: "Add retry visibility to webhook dashboard",
            project: "opshub",
            priority: .high,
            updatedTime: "31m ago"
        ),
        GitLabIssue(
            id: 9259,
            title: "Document local Elasticsearch bootstrap flow",
            project: "social-api",
            priority: .medium,
            updatedTime: "3h ago"
        ),
        GitLabIssue(
            id: 9246,
            title: "Review stale Homebrew package metadata",
            project: "opshub",
            priority: .low,
            updatedTime: "Yesterday"
        )
    ]

    static let notifications: [GitLabNotification] = [
        GitLabNotification(
            id: 712,
            title: "Nobi requested your review on tag sync changes",
            project: "social-api",
            kind: .reviewRequested,
            updatedTime: "5m ago"
        ),
        GitLabNotification(
            id: 708,
            title: "You were mentioned in retry worker discussion",
            project: "harasocial-services",
            kind: .mentioned,
            updatedTime: "24m ago"
        ),
        GitLabNotification(
            id: 703,
            title: "Pipeline failed on release packaging workflow",
            project: "opshub",
            kind: .pipelineFailed,
            updatedTime: "1h ago"
        )
    ]

    static let pipelines: [GitLabPipeline] = [
        GitLabPipeline(
            id: 45320,
            project: "social-api",
            branch: "feature/participant-tag-sync",
            status: .running,
            updatedTime: "3m ago"
        ),
        GitLabPipeline(
            id: 45312,
            project: "opshub",
            branch: "main",
            status: .passed,
            updatedTime: "18m ago"
        ),
        GitLabPipeline(
            id: 45298,
            project: "harasocial-services",
            branch: "fix/retry-timeout",
            status: .failed,
            updatedTime: "42m ago"
        )
    ]
}
