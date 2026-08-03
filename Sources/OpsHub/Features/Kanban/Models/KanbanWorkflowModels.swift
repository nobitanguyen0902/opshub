import Foundation

enum KanbanStage: String, Codable, Sendable { case architect, developer, reviewer }

enum KanbanPhase: String, Codable, Sendable {
    case triage, active, approvalRequired, blocked, needsAttention, done
}

struct KanbanStageReference: Codable, Equatable, Sendable {
    let stage: KanbanStage
    let attempt: Int
    let hermesTaskID: String
    let idempotencyKey: String
    let createdAt: Date
}

struct KanbanPendingTransition: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case createStage, cancel, retry, approve }

    let kind: Kind
    let stage: KanbanStage?
    let attempt: Int?
    let idempotencyKey: String
    let previousPhase: KanbanPhase?
    let previousHandoffSummary: String?
    let cancelReclaimAttempted: Bool?
    let cancelReclaimed: Bool?
    let cancelPreReclaimStatus: HermesKanbanStatus?
    let startedAt: Date

    init(
        kind: Kind,
        stage: KanbanStage?,
        attempt: Int?,
        idempotencyKey: String,
        previousPhase: KanbanPhase?,
        previousHandoffSummary: String? = nil,
        cancelReclaimAttempted: Bool? = nil,
        cancelReclaimed: Bool? = nil,
        cancelPreReclaimStatus: HermesKanbanStatus? = nil,
        startedAt: Date
    ) {
        self.kind = kind
        self.stage = stage
        self.attempt = attempt
        self.idempotencyKey = idempotencyKey
        self.previousPhase = previousPhase
        self.previousHandoffSummary = previousHandoffSummary
        self.cancelReclaimAttempted = cancelReclaimAttempted
        self.cancelReclaimed = cancelReclaimed
        self.cancelPreReclaimStatus = cancelPreReclaimStatus
        self.startedAt = startedAt
    }
}

struct KanbanWorkflow: Identifiable, Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    var title: String
    var objective: String
    var acceptanceCriteria: [String]
    var workspacePath: String
    var priority: KanbanPriority
    var phase: KanbanPhase
    var currentStage: KanbanStage?
    var repairCount: Int
    var stageReferences: [KanbanStageReference]
    var pendingTransition: KanbanPendingTransition?
    var cancellationReason: String?
    var cancellationPreviousPhase: KanbanPhase? = nil
    var cancellationRequiresHermesUnblock: Bool? = nil
    var attentionReason: String? = nil
    let createdAt: Date
    var updatedAt: Date
}

struct KanbanDraftInput: Equatable, Sendable {
    let title: String
    let objective: String
    let acceptanceCriteria: [String]
    let workspacePath: String
    let priority: KanbanPriority
}

struct HermesKanbanTask: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let body: String?
    let assignee: String?
    let status: HermesKanbanStatus
    let priority: Int
    let tenant: String?
    let workspaceKind: String
    let workspacePath: String?
    let branchName: String?
    let projectID: String?
    let createdBy: String?
    let createdAt: Int?
    let startedAt: Int?
    let completedAt: Int?
    let result: String?

    var createdAtDate: Date? { createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var startedAtDate: Date? { startedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }
    var completedAtDate: Date? { completedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    enum CodingKeys: String, CodingKey {
        case id, title, body, assignee, status, priority, tenant, result
        case workspaceKind = "workspace_kind"
        case workspacePath = "workspace_path"
        case branchName = "branch_name"
        case projectID = "project_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

struct HermesRunMetadata: Codable, Equatable, Sendable {
    let schemaVersion: Int?
    let outcome: String?
    let summary: String?
    let risks: [String]?
    let changedFiles: [String]?
    let verification: [String]?
    let findings: [String]?
}

struct HermesKanbanRun: Identifiable, Codable, Equatable, Sendable {
    let id: Int
    let profile: String?
    let stepKey: String?
    let status: String
    let outcome: String?
    let summary: String?
    let error: String?
    let metadata: HermesRunMetadata?
    let workerPID: Int?
    let startedAt: Int
    let endedAt: Int?

    var startedAtDate: Date? { Date(timeIntervalSince1970: TimeInterval(startedAt)) }
    var endedAtDate: Date? { endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) } }

    enum CodingKeys: String, CodingKey {
        case id, profile, status, outcome, summary, error, metadata
        case stepKey = "step_key"
        case workerPID = "worker_pid"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct HermesKanbanComment: Codable, Equatable, Sendable {
    let author: String
    let body: String
    let createdAt: Int

    var createdAtDate: Date? { Date(timeIntervalSince1970: TimeInterval(createdAt)) }

    enum CodingKeys: String, CodingKey { case author, body; case createdAt = "created_at" }
}

struct HermesKanbanEvent: Codable, Equatable, Sendable {
    let kind: String
    let payload: String?
    let createdAt: Int
    let runID: Int?

    var createdAtDate: Date? { Date(timeIntervalSince1970: TimeInterval(createdAt)) }

    enum CodingKeys: String, CodingKey {
        case kind, payload
        case createdAt = "created_at"
        case runID = "run_id"
    }
}

struct HermesKanbanTaskDetail: Codable, Equatable, Sendable {
    let task: HermesKanbanTask
    let latestSummary: String?
    let parents: [String]
    let children: [String]
    let comments: [HermesKanbanComment]
    let events: [HermesKanbanEvent]
    let runs: [HermesKanbanRun]

    enum CodingKeys: String, CodingKey {
        case task, parents, children, comments, events, runs
        case latestSummary = "latest_summary"
    }
}

enum ArchitectOutcome: String, Codable, Sendable { case ready, approvalRequired = "approval_required", blocked }
enum DeveloperOutcome: String, Codable, Sendable { case completed, blocked, failed }
enum ReviewerOutcome: String, Codable, Sendable { case approved, changesRequested = "changes_requested", blocked }

private enum KanbanHandoffSchema {
    static let supportedVersion = 1

    static func validate(schemaVersion: Int, decoder: Decoder) throws {
        guard schemaVersion == supportedVersion else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unsupported Kanban handoff schema version: \(schemaVersion)"
                )
            )
        }
    }
}

struct ArchitectHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: ArchitectOutcome
    let summary: String
    let risks: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try KanbanHandoffSchema.validate(schemaVersion: schemaVersion, decoder: decoder)

        self.schemaVersion = schemaVersion
        outcome = try container.decode(ArchitectOutcome.self, forKey: .outcome)
        summary = try container.decode(String.self, forKey: .summary)
        risks = try container.decode([String].self, forKey: .risks)
    }
}

struct DeveloperHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: DeveloperOutcome
    let summary: String
    let changedFiles: [String]
    let verification: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try KanbanHandoffSchema.validate(schemaVersion: schemaVersion, decoder: decoder)

        self.schemaVersion = schemaVersion
        outcome = try container.decode(DeveloperOutcome.self, forKey: .outcome)
        summary = try container.decode(String.self, forKey: .summary)
        changedFiles = try container.decode([String].self, forKey: .changedFiles)
        verification = try container.decode([String].self, forKey: .verification)
    }
}

struct ReviewerHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: ReviewerOutcome
    let summary: String
    let findings: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        try KanbanHandoffSchema.validate(schemaVersion: schemaVersion, decoder: decoder)

        self.schemaVersion = schemaVersion
        outcome = try container.decode(ReviewerOutcome.self, forKey: .outcome)
        summary = try container.decode(String.self, forKey: .summary)
        findings = try container.decode([String].self, forKey: .findings)
    }
}
