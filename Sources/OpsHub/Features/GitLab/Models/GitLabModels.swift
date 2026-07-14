import Foundation

/// A summary metric shown at the top of the GitLab dashboard.
struct GitLabStatistic: Identifiable, Hashable, Sendable {
    let icon: String
    let title: String
    let number: String
    let subtitle: String
    let webURL: URL?

    var id: String { title }
}

/// A merge request item formatted for the dashboard list.
struct GitLabMergeRequest: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let project: String
    let status: GitLabMergeRequestStatus
    let authorName: String?
    let authorAvatarURL: URL?
    let updatedTime: String
    let webURL: URL?

    init(
        id: Int,
        title: String,
        project: String,
        status: GitLabMergeRequestStatus,
        authorName: String? = nil,
        authorAvatarURL: URL? = nil,
        updatedTime: String,
        webURL: URL?
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.status = status
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.updatedTime = updatedTime
        self.webURL = webURL
    }
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
    let labels: [String]
    let labelDetails: [GitLabLabel]
    let isAssignedToMe: Bool
    let isWorkflowProject: Bool
    let assigneeName: String?
    let assigneeAvatarURL: URL?
    let updatedTime: String
    let webURL: URL?

    init(
        id: Int,
        title: String,
        project: String,
        priority: GitLabIssuePriority,
        labels: [String] = [],
        labelDetails: [GitLabLabel]? = nil,
        isAssignedToMe: Bool = true,
        isWorkflowProject: Bool = true,
        assigneeName: String? = nil,
        assigneeAvatarURL: URL? = nil,
        updatedTime: String,
        webURL: URL?
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.priority = priority
        self.labels = labels
        self.labelDetails = labelDetails ?? labels.map { GitLabLabel(name: $0) }
        self.isAssignedToMe = isAssignedToMe
        self.isWorkflowProject = isWorkflowProject
        self.assigneeName = assigneeName
        self.assigneeAvatarURL = assigneeAvatarURL
        self.updatedTime = updatedTime
        self.webURL = webURL
    }
}

/// The display details GitLab provides for an issue label.
struct GitLabLabel: Hashable, Sendable {
    let name: String
    let color: String?
    let textColor: String?

    init(name: String, color: String? = nil, textColor: String? = nil) {
        self.name = name
        self.color = color
        self.textColor = textColor
    }
}

/// The dashboard priority shown for an issue.
enum GitLabIssuePriority: String, Hashable, Sendable {
    case urgent = "Urgent"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
}

/// Filters available for the issue list on the GitLab dashboard.
enum GitLabIssueTab: String, CaseIterable, Identifiable, Sendable {
    case assignedToMe = "Assign me"
    case testing = "Test"
    case passed = "Passed"
    case build = "Build"
    case productionBug = "Bug Pro"

    var id: Self { self }

    func includes(_ issue: GitLabIssue) -> Bool {
        let labels = Set(issue.labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        return switch self {
        case .assignedToMe:
            issue.isAssignedToMe
        case .testing:
            issue.isWorkflowProject && (labels.contains("testing") || labels.contains("totest"))
        case .passed:
            issue.isWorkflowProject && labels.isSuperset(of: ["passed", "toproduction"])
        case .build:
            issue.isWorkflowProject && labels.isSuperset(of: ["passed", "toproduction", "merged"])
        case .productionBug:
            issue.isWorkflowProject && labels.contains("bug production")
        }
    }
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
enum GitLabConnectionTestResult: String, CaseIterable, Equatable, Sendable {
    case connected
    case unauthorized
    case timeout
}
