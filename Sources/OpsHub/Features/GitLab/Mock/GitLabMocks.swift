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
}
