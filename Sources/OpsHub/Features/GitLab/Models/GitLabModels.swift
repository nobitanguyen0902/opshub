import Foundation

/// Top-level destinations inside the GitLab workspace.
enum GitLabWorkspaceSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case mergeRequests
    case reviews
    case issues
    case pipelines
    case notifications

    var id: Self { self }

    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .mergeRequests:
            "Merge Requests"
        case .reviews:
            "Reviews"
        case .issues:
            "Issues"
        case .pipelines:
            "Pipelines"
        case .notifications:
            "Notifications"
        }
    }
}

/// The four compact metrics presented on the GitLab overview.
enum GitLabSummaryMetricKind: String, CaseIterable, Identifiable, Hashable, Sendable {
    case awaitingReview
    case assignedToMe
    case failedPipelines
    case unreadNotifications

    var id: Self { self }
}

/// Keeps count meanings explicit instead of overloading a single badge value.
struct GitLabCount: Equatable, Sendable {
    let total: Int
    let actionable: Int
    let unread: Int
    let visible: Int
}

/// Ordering used by the action-first overview queue.
enum GitLabActionPriority: Int, Comparable, CaseIterable, Sendable {
    case critical
    case high
    case normal
    case low

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Identifies a selected item without mixing resource identifier spaces.
enum GitLabWorkspaceItemID: Hashable, Sendable {
    case mergeRequest(Int)
    case review(Int)
    case issue(Int)
    case pipeline(Int)
    case notification(Int)
}

/// Shared workspace selection retained while navigating between sections.
struct GitLabWorkspaceSelection: Equatable, Sendable {
    var section: GitLabWorkspaceSection = .overview
    var item: GitLabWorkspaceItemID?
}

/// A project shown by the workspace scope selector.
struct GitLabProjectSummary: Identifiable, Hashable, Sendable {
    let id: Int
    let nameWithNamespace: String
    let webURL: URL?
}

/// Limits all workspace collections to one project or all membership projects.
enum GitLabProjectScope: Hashable, Sendable {
    case allProjects
    case project(GitLabProjectSummary)

    var title: String {
        switch self {
        case .allProjects:
            "All projects"
        case let .project(project):
            project.nameWithNamespace
        }
    }

    func includes(projectName: String) -> Bool {
        switch self {
        case .allProjects:
            true
        case let .project(project):
            project.nameWithNamespace.caseInsensitiveCompare(projectName) == .orderedSame
        }
    }
}

/// Additional filters retained independently for each workspace section.
struct GitLabWorkspaceFilter: Equatable, Sendable {
    var searchText: String
    var statuses: Set<String>
    var labels: Set<String>
    var participant: String?

    init(
        searchText: String = "",
        statuses: Set<String> = [],
        labels: Set<String> = [],
        participant: String? = nil
    ) {
        self.searchText = searchText
        self.statuses = statuses
        self.labels = labels
        self.participant = participant
    }

    var isEmpty: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && statuses.isEmpty
            && labels.isEmpty
            && participant?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
    }
}

enum GitLabWorkspaceSort: Equatable, Sendable {
    case actionablePriority
    case updatedDescending
}

/// Lifecycle for one independently loaded workspace section.
enum GitLabSectionLoadState: Equatable, Sendable {
    case idle
    case initialLoading
    case loaded
    case refreshing
    case stale(String)
    case failed(String)
}

/// Pure collection transformations shared by the ViewModel and tests.
enum GitLabWorkspaceFiltering {
    static func mergeRequests(
        _ items: [GitLabMergeRequest],
        scope: GitLabProjectScope,
        filter: GitLabWorkspaceFilter
    ) -> [GitLabMergeRequest] {
        items.filter { item in
            scope.includes(projectName: item.project)
                && matchesSearch(filter.searchText, values: ["!\(item.id)", item.title, item.project])
                && matchesStatuses(filter.statuses, value: item.status.rawValue)
                && matchesParticipant(filter.participant, value: item.authorName)
        }
    }

    static func issues(
        _ items: [GitLabIssue],
        scope: GitLabProjectScope,
        tab: GitLabIssueTab,
        filter: GitLabWorkspaceFilter
    ) -> [GitLabIssue] {
        items.filter { item in
            tab.includes(item)
                && scope.includes(projectName: item.project)
                && matchesSearch(filter.searchText, values: ["#\(item.id)", item.title, item.project])
                && matchesLabels(filter.labels, values: item.labels)
                && matchesParticipant(filter.participant, value: item.assigneeName)
        }
    }

    static func notifications(
        _ items: [GitLabNotification],
        scope: GitLabProjectScope,
        filter: GitLabWorkspaceFilter
    ) -> [GitLabNotification] {
        items.filter { item in
            scope.includes(projectName: item.project)
                && matchesSearch(filter.searchText, values: ["\(item.id)", item.title, item.project])
                && matchesStatuses(filter.statuses, value: item.kind.rawValue)
        }
    }

    static func pipelines(
        _ items: [GitLabPipeline],
        scope: GitLabProjectScope,
        filter: GitLabWorkspaceFilter
    ) -> [GitLabPipeline] {
        items.filter { item in
            scope.includes(projectName: item.project)
                && matchesSearch(filter.searchText, values: ["\(item.id)", item.branch, item.project])
                && matchesStatuses(filter.statuses, value: item.status.rawValue)
        }
    }

    static func sortMergeRequests(
        _ items: [GitLabMergeRequest],
        by sort: GitLabWorkspaceSort
    ) -> [GitLabMergeRequest] {
        switch sort {
        case .actionablePriority, .updatedDescending:
            items.sorted {
                if $0.updatedAt != $1.updatedAt {
                    return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
                }
                return $0.id > $1.id
            }
        }
    }

    static func sortIssues(_ items: [GitLabIssue]) -> [GitLabIssue] {
        items.sorted {
            if $0.updatedAt != $1.updatedAt {
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            return $0.id > $1.id
        }
    }

    static func sortNotifications(_ items: [GitLabNotification]) -> [GitLabNotification] {
        items.sorted {
            if $0.updatedAt != $1.updatedAt {
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            return $0.id > $1.id
        }
    }

    static func sortPipelines(_ items: [GitLabPipeline]) -> [GitLabPipeline] {
        items.sorted {
            if $0.updatedAt != $1.updatedAt {
                return ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast)
            }
            return $0.id > $1.id
        }
    }

    private static func matchesSearch(_ searchText: String, values: [String]) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        return values.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func matchesStatuses(_ statuses: Set<String>, value: String) -> Bool {
        guard statuses.isEmpty == false else { return true }
        let normalizedStatuses = Set(statuses.map(normalize))
        return normalizedStatuses.contains(normalize(value))
    }

    private static func matchesLabels(_ labels: Set<String>, values: [String]) -> Bool {
        guard labels.isEmpty == false else { return true }
        let normalizedValues = Set(values.map(normalize))
        return Set(labels.map(normalize)).isSubset(of: normalizedValues)
    }

    private static func matchesParticipant(_ participant: String?, value: String?) -> Bool {
        guard let participant else { return true }
        let query = participant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return true }
        return value?.localizedCaseInsensitiveContains(query) == true
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

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
    let updatedAt: Date?
    let updatedTime: String
    let webURL: URL?

    init(
        id: Int,
        title: String,
        project: String,
        status: GitLabMergeRequestStatus,
        authorName: String? = nil,
        authorAvatarURL: URL? = nil,
        updatedAt: Date? = nil,
        updatedTime: String,
        webURL: URL?
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.status = status
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.updatedAt = updatedAt
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
    let updatedAt: Date?
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
        updatedAt: Date? = nil,
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
        self.updatedAt = updatedAt
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
    let authorName: String?
    let authorAvatarURL: URL?
    let updatedAt: Date?
    let updatedTime: String
    let webURL: URL?

    init(
        id: Int,
        title: String,
        project: String,
        kind: GitLabNotificationKind,
        authorName: String? = nil,
        authorAvatarURL: URL? = nil,
        updatedAt: Date? = nil,
        updatedTime: String,
        webURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.project = project
        self.kind = kind
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.updatedAt = updatedAt
        self.updatedTime = updatedTime
        self.webURL = webURL
    }
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
    let userName: String?
    let userAvatarURL: URL?
    let updatedAt: Date?
    let updatedTime: String
    let webURL: URL?

    init(
        id: Int,
        project: String,
        branch: String,
        status: GitLabPipelineStatus,
        userName: String? = nil,
        userAvatarURL: URL? = nil,
        updatedAt: Date? = nil,
        updatedTime: String,
        webURL: URL? = nil
    ) {
        self.id = id
        self.project = project
        self.branch = branch
        self.status = status
        self.userName = userName
        self.userAvatarURL = userAvatarURL
        self.updatedAt = updatedAt
        self.updatedTime = updatedTime
        self.webURL = webURL
    }
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
