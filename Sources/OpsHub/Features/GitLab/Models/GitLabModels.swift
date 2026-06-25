import Foundation

struct GitLabStatistic: Identifiable, Hashable, Sendable {
    let icon: String
    let title: String
    let number: String
    let subtitle: String

    var id: String { title }
}

struct GitLabMergeRequest: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let status: GitLabMergeRequestStatus
    let updatedTime: String
}

enum GitLabMergeRequestStatus: String, Hashable, Sendable {
    case opened = "Open"
    case reviewing = "Reviewing"
    case approved = "Approved"
    case draft = "Draft"
}

struct GitLabIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let priority: GitLabIssuePriority
    let updatedTime: String
}

enum GitLabIssuePriority: String, Hashable, Sendable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

struct GitLabNotification: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let kind: GitLabNotificationKind
    let updatedTime: String
}

enum GitLabNotificationKind: String, Hashable, Sendable {
    case assigned = "Assigned"
    case mentioned = "Mentioned"
    case reviewRequested = "Review requested"
    case pipelineFailed = "Pipeline failed"
}

struct GitLabPipeline: Identifiable, Hashable, Sendable {
    let id: Int
    let project: String
    let branch: String
    let status: GitLabPipelineStatus
    let updatedTime: String
}

enum GitLabPipelineStatus: String, Hashable, Sendable {
    case running = "Running"
    case passed = "Passed"
    case failed = "Failed"
    case canceled = "Canceled"
}

enum GitLabConnectionTestResult: CaseIterable, Equatable, Sendable {
    case connected
    case unauthorized
    case timeout
}
