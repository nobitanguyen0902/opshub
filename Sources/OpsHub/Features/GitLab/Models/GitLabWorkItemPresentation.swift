import Foundation

enum GitLabWorkItemKind: String, Hashable, Sendable {
    case mergeRequest = "Merge request"
    case review = "Review"
    case issue = "Issue"
    case pipeline = "Pipeline"
    case notification = "Notification"
}

enum GitLabStatusSemantic: Hashable, Sendable {
    case information
    case success
    case warning
    case error
    case neutral
}

struct GitLabWorkItemStatus: Hashable, Sendable {
    let title: String
    let semantic: GitLabStatusSemantic
    let systemImage: String
}

struct GitLabWorkItemParticipant: Hashable, Sendable {
    let name: String
    let avatarURL: URL?
}

enum GitLabMergeRequestContext: Hashable, Sendable {
    case mergeRequest
    case review
}

struct GitLabWorkItemPresentation: Identifiable, Hashable, Sendable {
    let id: GitLabWorkspaceItemID
    let kind: GitLabWorkItemKind
    let reference: String
    let title: String
    let project: String
    let status: GitLabWorkItemStatus
    let priority: GitLabActionPriority
    let author: GitLabWorkItemParticipant?
    let participants: [GitLabWorkItemParticipant]
    let labels: [GitLabLabel]
    let updatedAt: Date?
    let updatedTime: String
    let webURL: URL?
    let resourceKey: GitLabResourceKey?

    var accessibilitySummary: String {
        let authorText = author.map { "Author \($0.name)" }
        let participantText: String
        switch kind {
        case .mergeRequest, .review:
            participantText = participants
                .map { "Assigned to \($0.name)" }
                .joined(separator: ", ")
        case .issue, .pipeline, .notification:
            participantText = participants.map(\.name).joined(separator: ", ")
        }
        return [
            "\(kind.rawValue) \(reference)",
            title,
            project,
            status.title,
            authorText,
            participantText.isEmpty ? nil : participantText,
            updatedTime
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    init(mergeRequest: GitLabMergeRequest, context: GitLabMergeRequestContext) {
        id = context == .review ? .review(mergeRequest.id) : .mergeRequest(mergeRequest.id)
        kind = context == .review ? .review : .mergeRequest
        reference = "!\(mergeRequest.iid)"
        title = mergeRequest.title
        project = mergeRequest.project
        status = Self.status(for: mergeRequest.status)
        priority = context == .review ? .high : .normal
        author = Self.participant(
            name: mergeRequest.authorName,
            avatarURL: mergeRequest.authorAvatarURL
        )
        participants = Self.participants(
            name: mergeRequest.assigneeName,
            avatarURL: mergeRequest.assigneeAvatarURL
        )
        labels = []
        updatedAt = mergeRequest.updatedAt
        updatedTime = mergeRequest.updatedTime
        webURL = mergeRequest.webURL
        resourceKey = GitLabResourceKey(kind: .mergeRequest, project: mergeRequest.project, id: mergeRequest.id)
    }

    init(issue: GitLabIssue) {
        id = .issue(issue.id)
        kind = .issue
        reference = "#\(issue.iid)"
        title = issue.title
        project = issue.project
        status = Self.status(for: issue.priority)
        priority = Self.actionPriority(for: issue.priority)
        author = nil
        participants = Self.participants(
            name: issue.assigneeName,
            avatarURL: issue.assigneeAvatarURL
        )
        labels = issue.labelDetails
        updatedAt = issue.updatedAt
        updatedTime = issue.updatedTime
        webURL = issue.webURL
        resourceKey = GitLabResourceKey(kind: .issue, project: issue.project, id: issue.id)
    }

    init(pipeline: GitLabPipeline) {
        id = .pipeline(pipeline.id)
        kind = .pipeline
        reference = "Pipeline #\(pipeline.id)"
        title = pipeline.branch
        project = pipeline.project
        status = Self.status(for: pipeline.status)
        priority = pipeline.status == .failed ? .critical : .low
        author = nil
        participants = Self.participants(
            name: pipeline.userName,
            avatarURL: pipeline.userAvatarURL
        )
        labels = []
        updatedAt = pipeline.updatedAt
        updatedTime = pipeline.updatedTime
        webURL = pipeline.webURL
        resourceKey = GitLabResourceKey(kind: .pipeline, project: pipeline.project, id: pipeline.id)
    }

    init(notification: GitLabNotification) {
        id = .notification(notification.id)
        kind = .notification
        reference = "TODO #\(notification.id)"
        title = notification.title
        project = notification.project
        status = Self.status(for: notification.kind)
        priority = Self.actionPriority(for: notification.kind)
        author = nil
        participants = Self.participants(
            name: notification.authorName,
            avatarURL: notification.authorAvatarURL
        )
        labels = []
        updatedAt = notification.updatedAt
        updatedTime = notification.updatedTime
        webURL = notification.webURL
        resourceKey = notification.targetResourceKey
    }

    private static func participants(
        name: String?,
        avatarURL: URL?
    ) -> [GitLabWorkItemParticipant] {
        [participant(name: name, avatarURL: avatarURL)].compactMap { $0 }
    }

    private static func participant(
        name: String?,
        avatarURL: URL?
    ) -> GitLabWorkItemParticipant? {
        guard let name else { return nil }
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedName.isEmpty == false else { return nil }
        return GitLabWorkItemParticipant(name: normalizedName, avatarURL: avatarURL)
    }

    private static func status(for status: GitLabMergeRequestStatus) -> GitLabWorkItemStatus {
        switch status {
        case .opened:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .success, systemImage: "circle")
        case .reviewing:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .warning, systemImage: "clock")
        case .approved:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .information, systemImage: "checkmark.circle")
        case .draft:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .neutral, systemImage: "pencil")
        }
    }

    private static func status(for priority: GitLabIssuePriority) -> GitLabWorkItemStatus {
        switch priority {
        case .urgent:
            GitLabWorkItemStatus(title: priority.rawValue, semantic: .error, systemImage: "exclamationmark.circle")
        case .high:
            GitLabWorkItemStatus(title: priority.rawValue, semantic: .warning, systemImage: "arrow.up.circle")
        case .medium:
            GitLabWorkItemStatus(title: priority.rawValue, semantic: .information, systemImage: "minus.circle")
        case .low:
            GitLabWorkItemStatus(title: priority.rawValue, semantic: .neutral, systemImage: "arrow.down.circle")
        }
    }

    private static func status(for status: GitLabPipelineStatus) -> GitLabWorkItemStatus {
        switch status {
        case .running:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .warning, systemImage: "clock.arrow.circlepath")
        case .passed:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .success, systemImage: "checkmark.circle")
        case .failed:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .error, systemImage: "xmark.circle")
        case .canceled:
            GitLabWorkItemStatus(title: status.rawValue, semantic: .neutral, systemImage: "slash.circle")
        }
    }

    private static func status(for kind: GitLabNotificationKind) -> GitLabWorkItemStatus {
        switch kind {
        case .assigned:
            GitLabWorkItemStatus(title: kind.rawValue, semantic: .information, systemImage: "person.crop.circle.badge.checkmark")
        case .mentioned:
            GitLabWorkItemStatus(title: kind.rawValue, semantic: .information, systemImage: "at")
        case .reviewRequested:
            GitLabWorkItemStatus(title: kind.rawValue, semantic: .warning, systemImage: "checkmark.bubble")
        case .pipelineFailed:
            GitLabWorkItemStatus(title: kind.rawValue, semantic: .error, systemImage: "xmark.circle")
        }
    }

    private static func actionPriority(for priority: GitLabIssuePriority) -> GitLabActionPriority {
        switch priority {
        case .urgent:
            .critical
        case .high:
            .high
        case .medium:
            .normal
        case .low:
            .low
        }
    }

    private static func actionPriority(for kind: GitLabNotificationKind) -> GitLabActionPriority {
        switch kind {
        case .pipelineFailed:
            .critical
        case .reviewRequested:
            .high
        case .assigned, .mentioned:
            .normal
        }
    }
}

enum GitLabActionQueueBuilder {
    static func build(
        reviews: [GitLabMergeRequest],
        issues: [GitLabIssue],
        pipelines: [GitLabPipeline],
        notifications: [GitLabNotification],
        scope: GitLabProjectScope
    ) -> [GitLabWorkItemPresentation] {
        let candidates = reviews
            .filter { scope.includes(projectName: $0.project) }
            .map { GitLabWorkItemPresentation(mergeRequest: $0, context: .review) }
            + issues
                .filter { $0.isAssignedToMe && scope.includes(projectName: $0.project) }
                .map(GitLabWorkItemPresentation.init(issue:))
            + pipelines
                .filter { $0.status == .failed && scope.includes(projectName: $0.project) }
                .map(GitLabWorkItemPresentation.init(pipeline:))
            + notifications
                .filter { scope.includes(projectName: $0.project) }
                .map(GitLabWorkItemPresentation.init(notification:))

        let unique = Dictionary(candidates.map { (dedupeKey(for: $0), $0) }, uniquingKeysWith: preferred)

        return unique.values.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
            if lhs.updatedAt != rhs.updatedAt {
                return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            }
            return lhs.accessibilitySummary < rhs.accessibilitySummary
        }
    }

    private enum DedupeKey: Hashable {
        case resource(GitLabResourceKey)
        case item(GitLabWorkspaceItemID)
    }

    private static func dedupeKey(for item: GitLabWorkItemPresentation) -> DedupeKey {
        item.resourceKey.map(DedupeKey.resource) ?? .item(item.id)
    }

    private static func preferred(
        _ first: GitLabWorkItemPresentation,
        _ second: GitLabWorkItemPresentation
    ) -> GitLabWorkItemPresentation {
        if first.priority != second.priority {
            return first.priority < second.priority ? first : second
        }
        if first.kind == .notification, second.kind != .notification { return second }
        if second.kind == .notification, first.kind != .notification { return first }
        return (first.updatedAt ?? .distantPast) >= (second.updatedAt ?? .distantPast) ? first : second
    }
}
