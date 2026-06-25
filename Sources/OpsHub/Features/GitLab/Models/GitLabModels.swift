import Foundation

/// A summary metric shown at the top of the GitLab dashboard.
struct GitLabStatistic: Identifiable, Hashable, Sendable {
    let icon: String
    let title: String
    let number: String
    let subtitle: String

    var id: String { title }
}

/// A merge request item formatted for the dashboard list.
struct GitLabMergeRequest: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let status: GitLabMergeRequestStatus
    let updatedTime: String
}

/// The dashboard status shown for a merge request.
enum GitLabMergeRequestStatus: String, Hashable, Sendable {
    case opened = "Open"
    case reviewing = "Reviewing"
    case approved = "Approved"
    case draft = "Draft"
}

/// An issue item formatted for the dashboard list.
struct GitLabIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let priority: GitLabIssuePriority
    let updatedTime: String
}

/// The dashboard priority shown for an issue.
enum GitLabIssuePriority: String, Hashable, Sendable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// A notification item formatted for future dashboard sections.
struct GitLabNotification: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let kind: GitLabNotificationKind
    let updatedTime: String
}

/// The category shown for a GitLab notification.
enum GitLabNotificationKind: String, Hashable, Sendable {
    case assigned = "Assigned"
    case mentioned = "Mentioned"
    case reviewRequested = "Review requested"
    case pipelineFailed = "Pipeline failed"
}

/// A pipeline item formatted for future dashboard sections.
struct GitLabPipeline: Identifiable, Hashable, Sendable {
    let id: Int
    let project: String
    let branch: String
    let status: GitLabPipelineStatus
    let updatedTime: String
}

/// The dashboard status shown for a pipeline.
enum GitLabPipelineStatus: String, Hashable, Sendable {
    case running = "Running"
    case passed = "Passed"
    case failed = "Failed"
    case canceled = "Canceled"
}

/// Result of checking whether the configured GitLab host and token are usable.
enum GitLabConnectionTestResult: CaseIterable, Equatable, Sendable {
    case connected
    case unauthorized
    case timeout
}
