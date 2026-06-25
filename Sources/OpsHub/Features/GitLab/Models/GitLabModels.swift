import Foundation

struct GitLabMergeRequest: Identifiable, Hashable {
    let id: Int
    let title: String
    let project: String
    let status: GitLabMergeRequestStatus
    let updatedTime: String
}

enum GitLabMergeRequestStatus: String, Hashable {
    case opened = "Open"
    case reviewing = "Reviewing"
    case approved = "Approved"
    case draft = "Draft"
}

struct GitLabIssue: Identifiable, Hashable {
    let id: Int
    let title: String
    let project: String
    let priority: GitLabIssuePriority
    let updatedTime: String
}

enum GitLabIssuePriority: String, Hashable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}
