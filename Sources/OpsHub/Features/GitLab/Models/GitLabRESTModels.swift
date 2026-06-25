import Foundation

struct MergeRequest: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int?
    let projectId: Int?
    let title: String
    let description: String?
    let state: State?
    let draft: Bool?
    let workInProgress: Bool?
    let sourceBranch: String?
    let targetBranch: String?
    let mergeStatus: String?
    let detailedMergeStatus: String?
    let blockingDiscussionsResolved: Bool?
    let labels: [String]
    let author: GitLabUser?
    let assignees: [GitLabUser]
    let reviewers: [GitLabUser]
    let pipeline: Pipeline?
    let headPipeline: Pipeline?
    let references: GitLabReferences?
    let upvotes: Int?
    let downvotes: Int?
    let userNotesCount: Int?
    let webUrl: URL?
    let createdAt: String?
    let updatedAt: String?
    let mergedAt: String?
    let closedAt: String?

    enum State: String, Codable, Hashable, Sendable {
        case opened
        case closed
        case locked
        case merged
    }

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectId = "project_id"
        case title
        case description
        case state
        case draft
        case workInProgress = "work_in_progress"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case mergeStatus = "merge_status"
        case detailedMergeStatus = "detailed_merge_status"
        case blockingDiscussionsResolved = "blocking_discussions_resolved"
        case labels
        case author
        case assignees
        case reviewers
        case pipeline
        case headPipeline = "head_pipeline"
        case references
        case upvotes
        case downvotes
        case userNotesCount = "user_notes_count"
        case webUrl = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case closedAt = "closed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        iid = try container.decodeIfPresent(Int.self, forKey: .iid)
        projectId = try container.decodeIfPresent(Int.self, forKey: .projectId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        state = try container.decodeIfPresent(State.self, forKey: .state)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft)
        workInProgress = try container.decodeIfPresent(Bool.self, forKey: .workInProgress)
        sourceBranch = try container.decodeIfPresent(String.self, forKey: .sourceBranch)
        targetBranch = try container.decodeIfPresent(String.self, forKey: .targetBranch)
        mergeStatus = try container.decodeIfPresent(String.self, forKey: .mergeStatus)
        detailedMergeStatus = try container.decodeIfPresent(String.self, forKey: .detailedMergeStatus)
        blockingDiscussionsResolved = try container.decodeIfPresent(Bool.self, forKey: .blockingDiscussionsResolved)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        author = try container.decodeIfPresent(GitLabUser.self, forKey: .author)
        assignees = try container.decodeIfPresent([GitLabUser].self, forKey: .assignees) ?? []
        reviewers = try container.decodeIfPresent([GitLabUser].self, forKey: .reviewers) ?? []
        pipeline = try container.decodeIfPresent(Pipeline.self, forKey: .pipeline)
        headPipeline = try container.decodeIfPresent(Pipeline.self, forKey: .headPipeline)
        references = try container.decodeIfPresent(GitLabReferences.self, forKey: .references)
        upvotes = try container.decodeIfPresent(Int.self, forKey: .upvotes)
        downvotes = try container.decodeIfPresent(Int.self, forKey: .downvotes)
        userNotesCount = try container.decodeIfPresent(Int.self, forKey: .userNotesCount)
        webUrl = try container.decodeIfPresent(URL.self, forKey: .webUrl)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        mergedAt = try container.decodeIfPresent(String.self, forKey: .mergedAt)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
    }
}

struct Issue: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int?
    let projectId: Int?
    let title: String
    let description: String?
    let state: State?
    let issueType: String?
    let labels: [String]
    let author: GitLabUser?
    let assignees: [GitLabUser]
    let milestone: GitLabMilestone?
    let references: GitLabReferences?
    let taskCompletionStatus: TaskCompletionStatus?
    let confidential: Bool?
    let discussionLocked: Bool?
    let upvotes: Int?
    let downvotes: Int?
    let userNotesCount: Int?
    let dueDate: String?
    let webUrl: URL?
    let createdAt: String?
    let updatedAt: String?
    let closedAt: String?

    enum State: String, Codable, Hashable, Sendable {
        case opened
        case closed
        case locked
    }

    struct TaskCompletionStatus: Codable, Hashable, Sendable {
        let count: Int?
        let completedCount: Int?

        enum CodingKeys: String, CodingKey {
            case count
            case completedCount = "completed_count"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectId = "project_id"
        case title
        case description
        case state
        case issueType = "issue_type"
        case labels
        case author
        case assignees
        case milestone
        case references
        case taskCompletionStatus = "task_completion_status"
        case confidential
        case discussionLocked = "discussion_locked"
        case upvotes
        case downvotes
        case userNotesCount = "user_notes_count"
        case dueDate = "due_date"
        case webUrl = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(Int.self, forKey: .id)
        iid = try container.decodeIfPresent(Int.self, forKey: .iid)
        projectId = try container.decodeIfPresent(Int.self, forKey: .projectId)
        title = try container.decode(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        state = try container.decodeIfPresent(State.self, forKey: .state)
        issueType = try container.decodeIfPresent(String.self, forKey: .issueType)
        labels = try container.decodeIfPresent([String].self, forKey: .labels) ?? []
        author = try container.decodeIfPresent(GitLabUser.self, forKey: .author)
        assignees = try container.decodeIfPresent([GitLabUser].self, forKey: .assignees) ?? []
        milestone = try container.decodeIfPresent(GitLabMilestone.self, forKey: .milestone)
        references = try container.decodeIfPresent(GitLabReferences.self, forKey: .references)
        taskCompletionStatus = try container.decodeIfPresent(TaskCompletionStatus.self, forKey: .taskCompletionStatus)
        confidential = try container.decodeIfPresent(Bool.self, forKey: .confidential)
        discussionLocked = try container.decodeIfPresent(Bool.self, forKey: .discussionLocked)
        upvotes = try container.decodeIfPresent(Int.self, forKey: .upvotes)
        downvotes = try container.decodeIfPresent(Int.self, forKey: .downvotes)
        userNotesCount = try container.decodeIfPresent(Int.self, forKey: .userNotesCount)
        dueDate = try container.decodeIfPresent(String.self, forKey: .dueDate)
        webUrl = try container.decodeIfPresent(URL.self, forKey: .webUrl)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        closedAt = try container.decodeIfPresent(String.self, forKey: .closedAt)
    }
}

struct Pipeline: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int?
    let projectId: Int?
    let sha: String?
    let ref: String?
    let status: Status?
    let source: String?
    let user: GitLabUser?
    let duration: Double?
    let queuedDuration: Double?
    let coverage: String?
    let webUrl: URL?
    let createdAt: String?
    let updatedAt: String?
    let startedAt: String?
    let finishedAt: String?

    enum Status: String, Codable, Hashable, Sendable {
        case created
        case waitingForResource = "waiting_for_resource"
        case preparing
        case pending
        case running
        case success
        case failed
        case canceled
        case skipped
        case manual
        case scheduled
    }

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectId = "project_id"
        case sha
        case ref
        case status
        case source
        case user
        case duration
        case queuedDuration = "queued_duration"
        case coverage
        case webUrl = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case startedAt = "started_at"
        case finishedAt = "finished_at"
    }
}

struct DashboardSummary: Codable, Hashable, Sendable {
    let mergeRequestCount: Int
    let issueCount: Int
    let pipelineCount: Int
    let notificationCount: Int
    let failedPipelineCount: Int
    let reviewRequestCount: Int

    init(
        mergeRequestCount: Int = 0,
        issueCount: Int = 0,
        pipelineCount: Int = 0,
        notificationCount: Int = 0,
        failedPipelineCount: Int = 0,
        reviewRequestCount: Int = 0
    ) {
        self.mergeRequestCount = mergeRequestCount
        self.issueCount = issueCount
        self.pipelineCount = pipelineCount
        self.notificationCount = notificationCount
        self.failedPipelineCount = failedPipelineCount
        self.reviewRequestCount = reviewRequestCount
    }

    enum CodingKeys: String, CodingKey {
        case mergeRequestCount = "merge_request_count"
        case issueCount = "issue_count"
        case pipelineCount = "pipeline_count"
        case notificationCount = "notification_count"
        case failedPipelineCount = "failed_pipeline_count"
        case reviewRequestCount = "review_request_count"
    }
}

struct Notification: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let project: GitLabProject?
    let author: GitLabUser?
    let actionName: String?
    let targetType: String?
    let targetUrl: URL?
    let body: String?
    let state: State?
    let target: Target?
    let createdAt: String?

    enum State: String, Codable, Hashable, Sendable {
        case pending
        case done
    }

    struct Target: Codable, Identifiable, Hashable, Sendable {
        let id: Int
        let iid: Int?
        let title: String?
        let type: String?
        let url: URL?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case id
            case iid
            case title
            case type
            case url
            case state
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case project
        case author
        case actionName = "action_name"
        case targetType = "target_type"
        case targetUrl = "target_url"
        case body
        case state
        case target
        case createdAt = "created_at"
    }
}

struct GitLabUser: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let username: String?
    let name: String?
    let state: String?
    let avatarUrl: URL?
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case name
        case state
        case avatarUrl = "avatar_url"
        case webUrl = "web_url"
    }
}

struct GitLabProject: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let description: String?
    let name: String?
    let nameWithNamespace: String?
    let path: String?
    let pathWithNamespace: String?
    let webUrl: URL?
    let avatarUrl: URL?
    let defaultBranch: String?
    let namespace: GitLabNamespace?

    enum CodingKeys: String, CodingKey {
        case id
        case description
        case name
        case nameWithNamespace = "name_with_namespace"
        case path
        case pathWithNamespace = "path_with_namespace"
        case webUrl = "web_url"
        case avatarUrl = "avatar_url"
        case defaultBranch = "default_branch"
        case namespace
    }
}

struct GitLabNamespace: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String?
    let path: String?
    let kind: String?
    let fullPath: String?
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case path
        case kind
        case fullPath = "full_path"
        case webUrl = "web_url"
    }
}

struct GitLabMilestone: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int?
    let projectId: Int?
    let title: String?
    let description: String?
    let state: String?
    let dueDate: String?
    let startDate: String?
    let webUrl: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case iid
        case projectId = "project_id"
        case title
        case description
        case state
        case dueDate = "due_date"
        case startDate = "start_date"
        case webUrl = "web_url"
    }
}

struct GitLabReferences: Codable, Hashable, Sendable {
    let short: String?
    let relative: String?
    let full: String?
}
