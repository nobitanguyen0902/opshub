enum GitLabMocks {
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
}
