# Kanban Task Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cho phép người dùng tạo một logical task trong OpsHub và tự động chạy workflow Hermes `architect → developer → reviewer` với approval, cancel, retry, repair loop, resume và UI Kanban đã duyệt.

**Architecture:** OpsHub lưu logical workflow index tại Application Support và điều phối từng stage; Hermes Kanban CLI/Gateway sở hữu task, run, result và log của agent. Mọi mutation đi qua CLI typed arguments, mọi quyết định state dựa trên JSON task/run metadata, và OpsHub không ghi trực tiếp SQLite.

**Tech Stack:** Swift 6, SwiftUI, Foundation `Process`, Codable JSON, XCTest, Hermes Kanban CLI, macOS 14.

## Global Constraints

- Chỉ chạy workflow khi canonical workspace path là Git repository có working tree sạch.
- Chỉ một active workflow trên mỗi canonical workspace path.
- Required Hermes profiles là `architect`, `developer`, `reviewer`.
- Start yêu cầu `hermes gateway status` thành công; OpsHub không tự start Gateway và không gọi global `hermes kanban dispatch`.
- Không ghi hoặc migrate `~/.hermes/kanban.db`; retire `KanbanSQLiteReader` sau khi CLI reader có regression coverage.
- Không parse log/human-readable output để quyết định workflow state; log text chỉ dùng để hiển thị.
- Reviewer được trả task cho Developer tối đa hai repair runs, sau đó logical task vào Needs Attention.
- Không commit, push, mở PR hoặc release nếu người dùng chưa yêu cầu rõ. Các commit command trong plan chỉ là checkpoint đề xuất; không chạy nếu chưa có authorization.
- Giữ `OpsHubTerminalTheme`, `OpsHubFeatureHeader`, accessibility focus, Reduce Motion và behavior đã duyệt.
- Không sửa hoặc xóa `.superpowers/brainstorm/3275-1785750842/`; đây là artifact có sẵn ngoài scope.

## File Structure

- `Sources/OpsHub/Features/Kanban/Models/KanbanModels.swift`: Hermes task/run/detail models, six-column projection và display data.
- `Sources/OpsHub/Features/Kanban/Models/KanbanWorkflowModels.swift`: logical task, draft input, stage, phase, priority, transition và handoff contracts.
- `Sources/OpsHub/Features/Kanban/Services/HermesKanbanService.swift`: protocol typed và CLI implementation cho list/show/runs/log/create/reclaim/block/unblock/capability checks.
- `Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowStore.swift`: atomic Codable persistence và schema validation.
- `Sources/OpsHub/Features/Kanban/Services/KanbanWorkspaceValidator.swift`: canonical path, Git repository, clean tree và active-workspace guard inputs.
- `Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowCoordinator.swift`: state machine, stage body builder, idempotency, reconciliation và recovery.
- `Sources/OpsHub/Features/Kanban/Services/KanbanColumnPreferences.swift`: collapsed-column preferences trong `UserDefaults`.
- `Sources/OpsHub/Features/Kanban/ViewModels/KanbanViewModel.swift`: refresh/polling, merged snapshot, selection và mutation loading state.
- `Sources/OpsHub/Features/Kanban/Views/KanbanView.swift`: feature composition, header, board, sheet và Inspector overlay.
- `Sources/OpsHub/Features/Kanban/Views/KanbanColumnView.swift`: expanded/collapsed column và card.
- `Sources/OpsHub/Features/Kanban/Views/KanbanNewTaskSheet.swift`: validated draft form.
- `Sources/OpsHub/Features/Kanban/Views/KanbanTaskInspector.swift`: Overview/Runs/Live Log và contextual actions.
- `Tests/OpsHubTests/KanbanDomainTests.swift`: domain projection và handoff decoding.
- `Tests/OpsHubTests/HermesKanbanServiceTests.swift`: CLI arguments, JSON fixtures và domain errors.
- `Tests/OpsHubTests/KanbanWorkflowStoreTests.swift`: persistence, schema và corruption.
- `Tests/OpsHubTests/KanbanWorkspaceValidatorTests.swift`: Git/path guards.
- `Tests/OpsHubTests/KanbanWorkflowCoordinatorTests.swift`: happy path, approval, cancel, retry, repair, idempotency và resume.
- `Tests/OpsHubTests/KanbanViewModelTests.swift`: merged snapshot, action gating và stale-data behavior.
- `Tests/OpsHubTests/KanbanViewTests.swift`: layout policies, collapse preferences, focus routers và Inspector actions.

---

### Task 1: Domain Models and Six-Column Projection

**Files:**
- Modify: `Sources/OpsHub/Features/Kanban/Models/KanbanModels.swift`
- Create: `Sources/OpsHub/Features/Kanban/Models/KanbanWorkflowModels.swift`
- Create: `Tests/OpsHubTests/KanbanDomainTests.swift`

**Interfaces:**
- Consumes: Hermes JSON task statuses `triage|todo|scheduled|ready|running|review|blocked|done|archived`.
- Produces: `KanbanColumn`, `HermesKanbanTask`, `HermesKanbanRun`, `HermesKanbanTaskDetail`, `KanbanWorkflow`, `KanbanDraftInput`, `KanbanStage`, `KanbanPhase`, `KanbanPriority`, `ArchitectHandoff`, `DeveloperHandoff`, `ReviewerHandoff`.

- [ ] **Step 1: Write failing projection and priority tests**

```swift
import XCTest
@testable import OpsHub

final class KanbanDomainTests: XCTestCase {
    func testHermesStatusesProjectIntoSixColumns() {
        XCTAssertEqual(KanbanColumn(status: .triage), .triage)
        XCTAssertEqual(KanbanColumn(status: .todo), .todo)
        XCTAssertEqual(KanbanColumn(status: .scheduled), .todo)
        XCTAssertEqual(KanbanColumn(status: .ready), .ready)
        XCTAssertEqual(KanbanColumn(status: .running), .running)
        XCTAssertEqual(KanbanColumn(status: .review), .running)
        XCTAssertEqual(KanbanColumn(status: .blocked), .blocked)
        XCTAssertEqual(KanbanColumn(status: .done), .done)
        XCTAssertNil(KanbanColumn(status: .archived))
    }

    func testPriorityMapsToHermesInteger() {
        XCTAssertEqual(KanbanPriority.allCases.map(\.hermesValue), [0, 1, 2, 3])
        XCTAssertEqual(KanbanPriority.normal.title, "Normal")
    }
}
```

- [ ] **Step 2: Run the domain tests and verify they fail**

Run: `swift test --filter KanbanDomainTests`

Expected: FAIL because the new domain types and projection do not exist.

- [ ] **Step 3: Define the exact domain enums and workflow record**

```swift
enum HermesKanbanStatus: String, Codable, Sendable {
    case triage, todo, scheduled, ready, running, review, blocked, done, archived
}

enum KanbanColumn: String, CaseIterable, Identifiable, Codable, Sendable {
    case triage, todo, ready, running, blocked, done
    var id: Self { self }

    init?(status: HermesKanbanStatus) {
        switch status {
        case .triage: self = .triage
        case .todo, .scheduled: self = .todo
        case .ready: self = .ready
        case .running, .review: self = .running
        case .blocked: self = .blocked
        case .done: self = .done
        case .archived: return nil
        }
    }
}

enum KanbanPriority: Int, CaseIterable, Codable, Sendable {
    case low = 0, normal = 1, high = 2, urgent = 3
    var hermesValue: Int { rawValue }
    var title: String { String(describing: self).capitalized }
}

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
    let startedAt: Date
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
    enum CodingKeys: String, CodingKey { case author, body; case createdAt = "created_at" }
}

struct HermesKanbanEvent: Codable, Equatable, Sendable {
    let kind: String
    let payload: String?
    let createdAt: Int
    let runID: Int?
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
```

Keep timestamps as epoch values in transport models and expose computed `Date?` properties for presentation so fixture decoding stays exact.

- [ ] **Step 4: Add strict stage handoff decoding tests and implementation**

```swift
func testReviewerHandoffRequiresFindingsArray() throws {
    let valid = #"{"schemaVersion":1,"outcome":"approved","summary":"LGTM","findings":[]}"#
    let handoff = try JSONDecoder().decode(ReviewerHandoff.self, from: Data(valid.utf8))
    XCTAssertEqual(handoff.outcome, .approved)

    let invalid = #"{"schemaVersion":1,"outcome":"approved","summary":"LGTM"}"#
    XCTAssertThrowsError(try JSONDecoder().decode(ReviewerHandoff.self, from: Data(invalid.utf8)))
}
```

Implement `ArchitectHandoff`, `DeveloperHandoff`, and `ReviewerHandoff` with required arrays and role-specific outcome enums from the design. Reject any `schemaVersion` other than `1` in a shared decoding validation method.

Use these exact types:

```swift
enum ArchitectOutcome: String, Codable, Sendable { case ready, approvalRequired = "approval_required", blocked }
enum DeveloperOutcome: String, Codable, Sendable { case completed, blocked, failed }
enum ReviewerOutcome: String, Codable, Sendable { case approved, changesRequested = "changes_requested", blocked }

struct ArchitectHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: ArchitectOutcome
    let summary: String
    let risks: [String]
}

struct DeveloperHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: DeveloperOutcome
    let summary: String
    let changedFiles: [String]
    let verification: [String]
}

struct ReviewerHandoff: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let outcome: ReviewerOutcome
    let summary: String
    let findings: [String]
}
```

- [ ] **Step 5: Run the focused tests**

Run: `swift test --filter KanbanDomainTests`

Expected: PASS.

- [ ] **Step 6: Record the commit checkpoint**

If and only if the user explicitly authorizes commits:

```bash
git add Sources/OpsHub/Features/Kanban/Models/KanbanModels.swift Sources/OpsHub/Features/Kanban/Models/KanbanWorkflowModels.swift Tests/OpsHubTests/KanbanDomainTests.swift
git commit -m "feat: define Kanban workflow domain"
```

### Task 2: Atomic Workflow Store and Column Preferences

**Files:**
- Create: `Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowStore.swift`
- Create: `Sources/OpsHub/Features/Kanban/Services/KanbanColumnPreferences.swift`
- Create: `Tests/OpsHubTests/KanbanWorkflowStoreTests.swift`
- Modify: `Tests/OpsHubTests/KanbanDomainTests.swift`

**Interfaces:**
- Consumes: `KanbanWorkflow.currentSchemaVersion`, `KanbanColumn`.
- Produces: `KanbanWorkflowStoring.load/save`, `KanbanColumnPreferences.collapsedColumns/setCollapsed`.

- [ ] **Step 1: Write failing persistence tests**

```swift
func testStoreRoundTripsWorkflowAtomically() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kanban-store-\(UUID().uuidString)/workflows.json")
    let store = FileKanbanWorkflowStore(url: url)
    let workflow = makeTriageWorkflow()

    try await store.save([workflow])

    XCTAssertEqual(try await store.load(), [workflow])
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
}

func testStoreRejectsUnsupportedSchema() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("kanban-schema-\(UUID().uuidString)/workflows.json")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let store = FileKanbanWorkflowStore(url: url)
    let data = #"[{"schemaVersion":99}]"#.data(using: .utf8)!
    try data.write(to: url)
    do {
        _ = try await store.load()
        XCTFail("Expected unsupported schema")
    } catch {
        XCTAssertEqual(error as? KanbanWorkflowStoreError, .unsupportedSchema(99))
    }
}

private func makeTriageWorkflow() -> KanbanWorkflow {
    KanbanWorkflow(
        schemaVersion: 1,
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal,
        phase: .triage,
        currentStage: nil,
        repairCount: 0,
        stageReferences: [],
        pendingTransition: nil,
        cancellationReason: nil,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}
```

Also test missing file returns `[]`, corrupt JSON produces `.corruptData`, and a failed save leaves the previously valid file readable.

- [ ] **Step 2: Run the store tests and verify they fail**

Run: `swift test --filter KanbanWorkflowStoreTests`

Expected: FAIL because store and preference types do not exist.

- [ ] **Step 3: Implement the actor-backed atomic store**

```swift
protocol KanbanWorkflowStoring: Sendable {
    func load() async throws -> [KanbanWorkflow]
    func save(_ workflows: [KanbanWorkflow]) async throws
}

enum KanbanWorkflowStoreError: LocalizedError, Equatable {
    case corruptData
    case unsupportedSchema(Int)
    case fileOperation(String)
}

actor FileKanbanWorkflowStore: KanbanWorkflowStoring {
    private let url: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(url: URL = Self.defaultURL(), fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    static func defaultURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpsHub/Kanban/workflows.json")
    }

    func save(_ workflows: [KanbanWorkflow]) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(workflows)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
```

On load, decode the full array, then validate every `schemaVersion` before returning any record. Never partially return a corrupt file.

- [ ] **Step 4: Implement and test collapsed-column preferences**

```swift
final class KanbanColumnPreferences {
    static let collapsedKey = "kanban.collapsedColumns"

    var collapsedColumns: Set<KanbanColumn> {
        Set(userDefaults.stringArray(forKey: Self.collapsedKey)?.compactMap(KanbanColumn.init(rawValue:)) ?? [])
    }

    func setCollapsed(_ collapsed: Bool, column: KanbanColumn) {
        var value = collapsedColumns
        if collapsed {
            value.insert(column)
        } else {
            value.remove(column)
        }
        userDefaults.set(value.map(\.rawValue).sorted(), forKey: Self.collapsedKey)
    }
}
```

Test save/restore with `UserDefaults(suiteName:)` and verify toggling one column preserves all others.

- [ ] **Step 5: Run focused tests**

Run: `swift test --filter KanbanWorkflowStoreTests && swift test --filter KanbanDomainTests`

Expected: PASS.

- [ ] **Step 6: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowStore.swift Sources/OpsHub/Features/Kanban/Services/KanbanColumnPreferences.swift Tests/OpsHubTests/KanbanWorkflowStoreTests.swift Tests/OpsHubTests/KanbanDomainTests.swift
git commit -m "feat: persist Kanban workflows and layout"
```

### Task 3: Hermes Kanban CLI Service

**Files:**
- Create: `Sources/OpsHub/Features/Kanban/Services/HermesKanbanService.swift`
- Create: `Tests/OpsHubTests/HermesKanbanServiceTests.swift`

**Interfaces:**
- Consumes: `ShellCommandRunning.run(_:arguments:)`, transport models from Task 1.
- Produces: `HermesKanbanServicing` methods below and `KanbanCommandError`.

- [ ] **Step 1: Define the protocol and write failing argument tests**

```swift
protocol HermesKanbanServicing: Sendable {
    func listTasks() async throws -> [HermesKanbanTask]
    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail
    func runs(taskID: String) async throws -> [HermesKanbanRun]
    func log(taskID: String, tailBytes: Int) async throws -> String
    func isAvailable() async -> Bool
    func profileExists(_ profile: String) async -> Bool
    func isGatewayRunning() async -> Bool
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask
    func reclaim(taskID: String, reason: String) async throws
    func block(taskID: String, reason: String) async throws
    func unblock(taskID: String, reason: String) async throws
}

struct HermesTaskCreateRequest: Equatable, Sendable {
    let title: String
    let body: String
    let assignee: String
    let workspacePath: String
    let priority: Int
    let idempotencyKey: String
}

enum KanbanCommandError: LocalizedError, Equatable {
    case launch(String)
    case permissionDenied(command: String)
    case timedOut(command: String)
    case failed(command: String, exitCode: Int32, stderr: String)
    case incompatibleJSON(command: String)
}
```

```swift
func testCreateUsesArgumentArrayAndJSON() async throws {
    let runner = RecordingShellRunner(stdout: TaskFixture.createdJSON)
    let service = HermesKanbanService(runner: runner)

    _ = try await service.createTask(.init(
        title: "Fix 'quoted' path",
        body: "Objective\nCriteria",
        assignee: "architect",
        workspacePath: "/tmp/project path",
        priority: 2,
        idempotencyKey: "opshub:workflow:architect:0"
    ))

    XCTAssertEqual(await runner.lastArguments, [
        "kanban", "create", "Fix 'quoted' path",
        "--body", "Objective\nCriteria",
        "--assignee", "architect",
        "--workspace", "dir:/tmp/project path",
        "--priority", "2",
        "--idempotency-key", "opshub:workflow:architect:0",
        "--created-by", "opshub",
        "--json"
    ])
}

private actor RecordingShellRunner: ShellCommandRunning {
    private(set) var lastArguments: [String] = []
    private let stdout: String

    init(stdout: String) { self.stdout = stdout }

    func run(_ command: String) async throws -> ShellCommandResult {
        try await run(command, arguments: [])
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        lastArguments = arguments
        return ShellCommandResult(stdout: stdout, stderr: "", exitCode: 0, duration: 0)
    }
}

private enum TaskFixture {
    static let createdJSON = #"{"id":"t_1","title":"Fix 'quoted' path","body":"Objective\nCriteria","assignee":"architect","status":"ready","priority":2,"tenant":null,"workspace_kind":"dir","workspace_path":"/tmp/project path","branch_name":null,"project_id":null,"created_by":"opshub","created_at":1,"started_at":null,"completed_at":null,"result":null}"#
}
```

- [ ] **Step 2: Run service tests and verify they fail**

Run: `swift test --filter HermesKanbanServiceTests`

Expected: FAIL because service and request do not exist.

- [ ] **Step 3: Implement typed read commands and strict JSON decoding**

Use only `runner.run("hermes", arguments: ...)`:

```swift
func listTasks() async throws -> [HermesKanbanTask] {
    try await decode([HermesKanbanTask].self, arguments: ["kanban", "list", "--json"])
}

func taskDetail(id: String) async throws -> HermesKanbanTaskDetail {
    try await decode(HermesKanbanTaskDetail.self, arguments: ["kanban", "show", id, "--json"])
}

func runs(taskID: String) async throws -> [HermesKanbanRun] {
    try await decode([HermesKanbanRun].self, arguments: ["kanban", "runs", taskID, "--json"])
}
```

Map `ShellCommandError` into `KanbanCommandError.launch`, `.permissionDenied`, `.timedOut`, or `.failed(command:exitCode:stderr:)`. Map JSON errors into `.incompatibleJSON(command:)`; never surface the Brew-specific localized message.

- [ ] **Step 4: Implement capability and mutation commands**

```swift
func profileExists(_ profile: String) async -> Bool {
    (try? await runner.run("hermes", arguments: ["profile", "show", profile])) != nil
}

func isAvailable() async -> Bool {
    (try? await runner.run("hermes", arguments: ["--version"])) != nil
}

func isGatewayRunning() async -> Bool {
    (try? await runner.run("hermes", arguments: ["gateway", "status"])) != nil
}

func reclaim(taskID: String, reason: String) async throws {
    _ = try await run(["kanban", "reclaim", taskID, "--reason", reason])
}

func block(taskID: String, reason: String) async throws {
    _ = try await run(["kanban", "block", taskID, "--kind", "needs_input", reason])
}

func unblock(taskID: String, reason: String) async throws {
    _ = try await run(["kanban", "unblock", taskID, "--reason", reason])
}
```

`log` returns stdout text only for display. Cap `tailBytes` to `1...1_000_000` before building `--tail`.

- [ ] **Step 5: Add fixture decoding and error regression tests**

Fixtures must include:

- list task with `status: "review"` and snake_case timestamps;
- show payload with task, latest_summary, parents, children, comments, events and runs;
- run metadata dictionary used by each handoff role;
- malformed JSON;
- nonzero exit with stderr;
- Hermes availability, gateway and profile checks based on exit status only.

Run: `swift test --filter HermesKanbanServiceTests`

Expected: PASS.

- [ ] **Step 6: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Services/HermesKanbanService.swift Tests/OpsHubTests/HermesKanbanServiceTests.swift
git commit -m "feat: add typed Hermes Kanban service"
```

### Task 4: Workspace Validation and Start Guards

**Files:**
- Create: `Sources/OpsHub/Features/Kanban/Services/KanbanWorkspaceValidator.swift`
- Create: `Tests/OpsHubTests/KanbanWorkspaceValidatorTests.swift`

**Interfaces:**
- Consumes: `ShellCommandRunning`.
- Produces: `KanbanWorkspaceValidating.validateDraftPath`, `validateStart`, `KanbanStartGuardError`.

- [ ] **Step 1: Write failing path and Git guard tests**

```swift
func testDraftValidationRejectsNonGitDirectory() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("not-a-repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let failure = ShellCommandResult(stdout: "", stderr: "not a git repository", exitCode: 128, duration: 0)
    let validator = KanbanWorkspaceValidator(runner: WorkspaceRunner(results: [.failure(.commandFailed(failure))]))
    do {
        _ = try await validator.validateDraftPath(directoryURL)
        XCTFail("Expected notGitRepository")
    } catch {
        XCTAssertEqual(error as? KanbanStartGuardError, .notGitRepository)
    }
}

func testStartRejectsDirtyWorkingTree() async throws {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("repo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    let runner = WorkspaceRunner(results: [
        .success(.init(stdout: directoryURL.path + "\n", stderr: "", exitCode: 0, duration: 0)),
        .success(.init(stdout: " M Sources/File.swift\n", stderr: "", exitCode: 0, duration: 0))
    ])
    let validator = KanbanWorkspaceValidator(runner: runner)
    do {
        _ = try await validator.validateStart(directoryURL)
        XCTFail("Expected dirtyWorkingTree")
    } catch {
        XCTAssertEqual(error as? KanbanStartGuardError, .dirtyWorkingTree([" M Sources/File.swift"]))
    }
}

private actor WorkspaceRunner: ShellCommandRunning {
    var results: [Result<ShellCommandResult, ShellCommandError>]
    init(results: [Result<ShellCommandResult, ShellCommandError>]) { self.results = results }
    func run(_ command: String) async throws -> ShellCommandResult { try await run(command, arguments: []) }
    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        try results.removeFirst().get()
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter KanbanWorkspaceValidatorTests`

Expected: FAIL because validator types do not exist.

- [ ] **Step 3: Implement canonicalization and Git checks**

```swift
protocol KanbanWorkspaceValidating: Sendable {
    func validateDraftPath(_ url: URL) async throws -> URL
    func validateStart(_ url: URL) async throws -> URL
}

enum KanbanStartGuardError: LocalizedError, Equatable {
    case missingDirectory
    case notGitRepository
    case notRepositoryRoot
    case dirtyWorkingTree([String])
    case hermesUnavailable
    case missingProfile(String)
    case gatewayStopped
    case workspaceAlreadyActive(UUID)
}

func validateDraftPath(_ url: URL) async throws -> URL {
    let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw KanbanStartGuardError.missingDirectory
    }
    let result: ShellCommandResult
    do {
        result = try await runner.run("git", arguments: ["-C", canonical.path, "rev-parse", "--show-toplevel"])
    } catch {
        throw KanbanStartGuardError.notGitRepository
    }
    guard URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).standardizedFileURL == canonical else {
        throw KanbanStartGuardError.notRepositoryRoot
    }
    return canonical
}
```

`validateStart` calls draft validation again, then `git -C <path> status --porcelain`; any non-empty line becomes `.dirtyWorkingTree(lines)`.

- [ ] **Step 4: Add canonical-root regression tests**

Test a nested directory returns `.notRepositoryRoot`, a symlink to the repository root resolves to the same canonical URL, and clean `status --porcelain` output succeeds.

Run: `swift test --filter KanbanWorkspaceValidatorTests`

Expected: PASS for a clean canonical root; explicit failures for missing directory, non-Git directory, nested directory and dirty tree.

- [ ] **Step 5: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Services/KanbanWorkspaceValidator.swift Tests/OpsHubTests/KanbanWorkspaceValidatorTests.swift
git commit -m "feat: validate Kanban workflow start"
```

### Task 5: Workflow Coordinator Happy Path

**Files:**
- Create: `Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowCoordinator.swift`
- Create: `Tests/OpsHubTests/KanbanWorkflowCoordinatorTests.swift`

**Interfaces:**
- Consumes: `KanbanWorkflowStoring`, `HermesKanbanServicing`, `KanbanWorkspaceValidating`, Task 1 handoff models.
- Produces: `KanbanWorkflowCoordinating.createDraft/start/refresh/workflows` and deterministic stage requests.

- [ ] **Step 1: Write failing draft and Start tests**

```swift
func testCreateDraftPersistsTriageWithoutCreatingHermesTask() async throws {
    let harness = makeCoordinatorHarness()
    let draft = try await harness.coordinator.createDraft(makeDraftInput())

    XCTAssertEqual(draft.phase, .triage)
    XCTAssertNil(draft.currentStage)
    XCTAssertEqual(await harness.hermes.createdRequests.count, 0)
}

func testStartCreatesArchitectStageAfterAllGuardsPass() async throws {
    let harness = makeCoordinatorHarness()
    let draft = try await harness.coordinator.createDraft(makeDraftInput())
    let started = try await harness.coordinator.start(workflowID: draft.id)

    XCTAssertEqual(started.phase, .active)
    XCTAssertEqual(started.currentStage, .architect)
    XCTAssertEqual(await harness.hermes.createdRequests.first?.assignee, "architect")
    XCTAssertEqual(await harness.hermes.createdRequests.first?.idempotencyKey, "opshub:\(draft.id.uuidString.lowercased()):architect:0")
}

private struct CoordinatorHarness {
    let coordinator: KanbanWorkflowCoordinator
    let hermes: StubHermesKanbanService
}

private func makeCoordinatorHarness(workflows: [KanbanWorkflow] = []) -> CoordinatorHarness {
    let store = InMemoryWorkflowStore(workflows)
    let hermes = StubHermesKanbanService()
    let coordinator = KanbanWorkflowCoordinator(
        store: store,
        hermes: hermes,
        workspaceValidator: StubWorkspaceValidator(),
        now: { Date(timeIntervalSince1970: 1) }
    )
    return CoordinatorHarness(coordinator: coordinator, hermes: hermes)
}

private func makeDraftInput() -> KanbanDraftInput {
    KanbanDraftInput(
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal
    )
}

private func makeTriageWorkflow() -> KanbanWorkflow {
    KanbanWorkflow(
        schemaVersion: 1,
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal,
        phase: .triage,
        currentStage: nil,
        repairCount: 0,
        stageReferences: [],
        pendingTransition: nil,
        cancellationReason: nil,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}

private actor InMemoryWorkflowStore: KanbanWorkflowStoring {
    private var value: [KanbanWorkflow]
    init(_ value: [KanbanWorkflow] = []) { self.value = value }
    func load() -> [KanbanWorkflow] { value }
    func save(_ workflows: [KanbanWorkflow]) { value = workflows }
}

private struct StubWorkspaceValidator: KanbanWorkspaceValidating {
    func validateDraftPath(_ url: URL) async throws -> URL { url.standardizedFileURL }
    func validateStart(_ url: URL) async throws -> URL { url.standardizedFileURL }
}

private actor StubHermesKanbanService: HermesKanbanServicing {
    private(set) var createdRequests: [HermesTaskCreateRequest] = []
    private var details: [String: HermesKanbanTaskDetail] = [:]

    func listTasks() async throws -> [HermesKanbanTask] { details.values.map(\.task) }
    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail { try XCTUnwrap(details[id]) }
    func runs(taskID: String) async throws -> [HermesKanbanRun] { try XCTUnwrap(details[taskID]).runs }
    func log(taskID: String, tailBytes: Int) async throws -> String { "" }
    func isAvailable() async -> Bool { true }
    func profileExists(_ profile: String) async -> Bool { ["architect", "developer", "reviewer"].contains(profile) }
    func isGatewayRunning() async -> Bool { true }
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask {
        createdRequests.append(request)
        return HermesKanbanTask.fixture(id: "t_\(createdRequests.count)", request: request)
    }
    func reclaim(taskID: String, reason: String) async throws {}
    func block(taskID: String, reason: String) async throws {}
    func unblock(taskID: String, reason: String) async throws {}
    func setDetail(_ detail: HermesKanbanTaskDetail) { details[detail.task.id] = detail }
}

private extension HermesKanbanTask {
    static func fixture(id: String, request: HermesTaskCreateRequest) -> Self {
        HermesKanbanTask(
            id: id,
            title: request.title,
            body: request.body,
            assignee: request.assignee,
            status: .ready,
            priority: request.priority,
            tenant: nil,
            workspaceKind: "dir",
            workspacePath: request.workspacePath,
            branchName: nil,
            projectID: nil,
            createdBy: "opshub",
            createdAt: 1,
            startedAt: nil,
            completedAt: nil,
            result: nil
        )
    }
}
```

- [ ] **Step 2: Run coordinator tests and verify they fail**

Run: `swift test --filter KanbanWorkflowCoordinatorTests`

Expected: FAIL because coordinator does not exist.

- [ ] **Step 3: Implement createDraft, workflow loading and guarded Start**

```swift
protocol KanbanWorkflowCoordinating: Sendable {
    func workflows() async throws -> [KanbanWorkflow]
    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow
    func start(workflowID: UUID) async throws -> KanbanWorkflow
    func refresh() async throws -> [KanbanWorkflow]
}

enum KanbanWorkflowError: LocalizedError, Equatable {
    case workflowNotFound(UUID)
    case invalidPhase(KanbanPhase)
    case invalidDraft
    case invalidHandoff(KanbanStage)
    case missingCurrentTask
    case unsafeRecovery
}
```

`createDraft` trims title/objective, removes empty acceptance-criteria lines, rejects any empty required value, calls `validateDraftPath`, and stores only the returned canonical root path. It creates `schemaVersion = 1`, `.triage`, no stage references and no pending transition. Validation failure must leave the store unchanged.

Before writing `pendingTransition`, `start` must:

1. call `workspaceValidator.validateStart`;
2. reject another workflow whose phase is `.active` or `.approvalRequired` and whose standardized, symlink-resolved path matches;
3. require `isAvailable() == true` before checking profiles;
4. call `profileExists` for `architect`, `developer`, and `reviewer`, failing on the first missing profile;
5. require `isGatewayRunning() == true`.

Add one coordinator test for each guard and assert `hermes.createdRequests` stays empty on failure.

Store a `.createStage` pending transition before calling Hermes. Use a deterministic `stageKey` helper:

```swift
func stageKey(workflowID: UUID, stage: KanbanStage, attempt: Int) -> String {
    "opshub:\(workflowID.uuidString.lowercased()):\(stage.rawValue):\(attempt)"
}
```

Create stages with `workspace: dir:<canonical path>`, numeric priority, `created-by: opshub`, exact role assignee and `--json`.

- [ ] **Step 4: Implement the exact stage prompt builder**

The body must contain the logical contract, previous handoff summaries and this terminal instruction:

```text
Complete this Hermes task with metadata JSON schemaVersion=1.
Architect outcomes: ready | approval_required | blocked; include risks[].
Developer outcomes: completed | blocked | failed; include changedFiles[] and verification[].
Reviewer outcomes: approved | changes_requested | blocked; include findings[].
Do not claim success unless the required work and verification are complete.
```

Architect and Reviewer prompts explicitly state read-only. Developer prompt states it may modify only the selected workspace and must preserve unrelated user changes.

- [ ] **Step 5: Implement reconciliation through the happy path**

`refresh()` loads the current Hermes task detail and latest terminal run for each active workflow. When metadata decodes:

- Architect `ready` creates Developer attempt `0`.
- Developer `completed` creates Reviewer attempt `0`.
- Reviewer `approved` marks logical workflow Done.

Convert transport metadata with strict role helpers; do not default missing arrays to empty:

```swift
func architectHandoff(from metadata: HermesRunMetadata) throws -> ArchitectHandoff {
    guard
        let version = metadata.schemaVersion,
        let rawOutcome = metadata.outcome,
        let outcome = ArchitectOutcome(rawValue: rawOutcome),
        let summary = metadata.summary,
        let risks = metadata.risks,
        version == 1
    else { throw KanbanWorkflowError.invalidHandoff(.architect) }
    return ArchitectHandoff(schemaVersion: version, outcome: outcome, summary: summary, risks: risks)
}
```

Implement equivalent Developer and Reviewer helpers requiring their exact arrays. Also require the latest run to be terminal (`endedAt != nil`) and its `profile` to match the current stage before consuming metadata.

Before every create, persist pending transition; after create, append `KanbanStageReference`, clear pending transition and save. Re-reading the same terminal run must not create another stage.

- [ ] **Step 6: Run happy-path and idempotency tests**

Add a test that calls `refresh()` twice with the same Architect terminal run and asserts exactly one Developer request.

Run: `swift test --filter KanbanWorkflowCoordinatorTests`

Expected: PASS for draft, Start, happy path and repeated refresh.

- [ ] **Step 7: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowCoordinator.swift Tests/OpsHubTests/KanbanWorkflowCoordinatorTests.swift
git commit -m "feat: orchestrate Kanban workflow stages"
```

### Task 6: Approval, Cancel, Retry, Repair Loop, and Resume

**Files:**
- Modify: `Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowCoordinator.swift`
- Modify: `Tests/OpsHubTests/KanbanWorkflowCoordinatorTests.swift`

**Interfaces:**
- Consumes: coordinator and Hermes mutations from Tasks 3–5.
- Produces: `approve`, `cancel`, `retry`, `resumePendingTransitions` and exceptional state transitions.

- [ ] **Step 1: Write failing approval and repair-loop tests**

```swift
func testArchitectApprovalRequiredDoesNotCreateDeveloper() async throws {
    let workflow = makeActiveWorkflow(stage: .architect, repairCount: 0, taskID: "t_architect")
    let harness = makeCoordinatorHarness(workflows: [workflow])
    await harness.hermes.setDetail(makeTerminalDetail(
        taskID: "t_architect",
        profile: "architect",
        metadata: .init(
            schemaVersion: 1,
            outcome: "approval_required",
            summary: "Breaking API",
            risks: ["breaking API"],
            changedFiles: nil,
            verification: nil,
            findings: nil
        )
    ))
    let values = try await harness.coordinator.refresh()
    let refreshed = try XCTUnwrap(values.first)

    XCTAssertEqual(refreshed.phase, .approvalRequired)
    XCTAssertEqual(await harness.hermes.createdRequests.count, 0)
}

func testThirdChangesRequestedStopsAtNeedsAttention() async throws {
    let workflow = makeActiveWorkflow(stage: .reviewer, repairCount: 2, taskID: "t_reviewer")
    let harness = makeCoordinatorHarness(workflows: [workflow])
    await harness.hermes.setDetail(makeTerminalDetail(
        taskID: "t_reviewer",
        profile: "reviewer",
        metadata: .init(
            schemaVersion: 1,
            outcome: "changes_requested",
            summary: "Still failing",
            risks: nil,
            changedFiles: nil,
            verification: nil,
            findings: ["still failing"]
        )
    ))
    let values = try await harness.coordinator.refresh()
    let refreshed = try XCTUnwrap(values.first)

    XCTAssertEqual(refreshed.phase, .needsAttention)
    XCTAssertEqual(await harness.hermes.createdRequests.count, 0)
}

private func makeActiveWorkflow(stage: KanbanStage, repairCount: Int, taskID: String) -> KanbanWorkflow {
    var value = makeTriageWorkflow()
    value.phase = .active
    value.currentStage = stage
    value.repairCount = repairCount
    value.stageReferences = [.init(
        stage: stage,
        attempt: repairCount,
        hermesTaskID: taskID,
        idempotencyKey: "opshub:test:\(stage.rawValue):\(repairCount)",
        createdAt: Date(timeIntervalSince1970: 1)
    )]
    return value
}

private func makeTerminalDetail(
    taskID: String,
    profile: String,
    metadata: HermesRunMetadata
) -> HermesKanbanTaskDetail {
    let request = HermesTaskCreateRequest(
        title: "Task",
        body: "Body",
        assignee: profile,
        workspacePath: "/tmp/repo",
        priority: 1,
        idempotencyKey: "test"
    )
    return HermesKanbanTaskDetail(
        task: .fixture(id: taskID, request: request),
        latestSummary: metadata.summary,
        parents: [],
        children: [],
        comments: [],
        events: [],
        runs: [.init(
            id: 1,
            profile: profile,
            stepKey: nil,
            status: "completed",
            outcome: "completed",
            summary: metadata.summary,
            error: nil,
            metadata: metadata,
            workerPID: nil,
            startedAt: 1,
            endedAt: 2
        )]
    )
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter KanbanWorkflowCoordinatorTests`

Expected: FAIL at missing exceptional transitions.

- [ ] **Step 3: Implement approval and repair transitions**

Extend protocol:

```swift
func approve(workflowID: UUID) async throws -> KanbanWorkflow
func cancel(workflowID: UUID) async throws -> KanbanWorkflow
func retry(workflowID: UUID) async throws -> KanbanWorkflow
func resumePendingTransitions() async throws -> [KanbanWorkflow]
```

`approve` is valid only in `.approvalRequired`, writes `.approve` pending transition, creates Developer with the next deterministic attempt key, then clears pending transition. `changes_requested` increments `repairCount`, creates Developer repair and then Reviewer with matching attempt. If `repairCount == 2`, set `.needsAttention` without creating another task.

- [ ] **Step 4: Implement two-step Cancel with partial-failure handling**

For a running Hermes task:

```swift
try await hermes.reclaim(taskID: taskID, reason: "Cancelled by user")
do {
    try await hermes.block(taskID: taskID, reason: "Cancelled by user")
} catch {
    workflow.phase = .needsAttention
    workflow.cancellationReason = "Reclaimed but failed to block: \(error.localizedDescription)"
    try await persist(workflow)
    throw error
}
```

For approval/between-stage Cancel, persist previous phase in the pending transition recovery payload, set logical `.blocked`, and do not issue reclaim. Reconcile task status after both Hermes mutation commands before reporting success.

- [ ] **Step 5: Implement Retry for Hermes-blocked and local-cancelled states**

- Hermes blocked: persist `.retry`, call `unblock`, read `show --json`, require status `ready|running`, then restore `.active`.
- Local cancelled: restore the saved phase; Approval Required returns to the gate and never auto-approves.
- Neither path changes `repairCount` or deletes a stage reference.

- [ ] **Step 6: Implement crash-resume cases**

Tests must cover app restart after:

1. pending create persisted, Hermes task not created;
2. Hermes task created, stage reference not persisted;
3. reclaim succeeded, block not yet called;
4. approve persisted, Developer task already created.

For pending stage creation, `resumePendingTransitions()` repeats `hermes kanban create` with the same idempotency key; Hermes returns the existing task ID if the first create already committed. It then reconciles that returned ID with `show --json` before saving the stage reference. For non-create transitions it reconciles the current referenced task before issuing the missing mutation. If it cannot prove a safe next step, it sets `.needsAttention` instead of guessing.

- [ ] **Step 7: Run all coordinator tests**

Run: `swift test --filter KanbanWorkflowCoordinatorTests`

Expected: PASS for happy path, approval, blocked outcomes, cancel partial failure, retry, two repairs and all resume checkpoints.

- [ ] **Step 8: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Services/KanbanWorkflowCoordinator.swift Tests/OpsHubTests/KanbanWorkflowCoordinatorTests.swift
git commit -m "feat: recover Kanban workflow actions"
```

### Task 7: View Model and CLI-Backed Board Migration

**Files:**
- Modify: `Sources/OpsHub/Features/Kanban/ViewModels/KanbanViewModel.swift`
- Modify: `Sources/OpsHub/Features/Kanban/Models/KanbanModels.swift`
- Create: `Tests/OpsHubTests/KanbanViewModelTests.swift`
- Modify: `Tests/OpsHubTests/KanbanTests.swift`

**Interfaces:**
- Consumes: `HermesKanbanServicing`, `KanbanWorkflowCoordinating`, column projection.
- Produces: `KanbanBoardSnapshot`, `KanbanCardViewData`, selected Inspector state and action methods.

- [ ] **Step 1: Write failing merged-snapshot and stale-data tests**

```swift
@MainActor
func testRefreshMergesLogicalWorkflowsAndExternalHermesTasks() async {
    var workflow = makeTriageWorkflow()
    workflow.title = "OpsHub workflow"
    let request = HermesTaskCreateRequest(
        title: "External task", body: "", assignee: "developer",
        workspacePath: "/tmp/external", priority: 1, idempotencyKey: "external"
    )
    let model = KanbanViewModel(
        hermes: ViewModelHermesStub(tasks: [.fixture(id: "t_external", request: request)]),
        coordinator: ViewModelCoordinatorStub(workflows: [workflow])
    )

    await model.refresh()

    XCTAssertEqual(model.snapshot?.cards.map(\.title), ["OpsHub workflow", "External task"])
    XCTAssertTrue(model.snapshot?.cards.first?.isWorkflowOwned == true)
    XCTAssertFalse(model.snapshot?.cards.last?.isWorkflowOwned == true)
}

@MainActor
func testRefreshFailureKeepsPreviousSnapshot() async {
    let hermes = ViewModelHermesStub(
        taskResults: [.success([]), .failure(.incompatibleJSON(command: "list"))]
    )
    let model = KanbanViewModel(
        hermes: hermes,
        coordinator: ViewModelCoordinatorStub(workflows: [])
    )
    await model.refresh()
    let previous = model.snapshot
    await model.refresh()
    XCTAssertEqual(model.snapshot, previous)
    XCTAssertNotNil(model.errorMessage)
}

private actor ViewModelHermesStub: HermesKanbanServicing {
    private var taskResults: [Result<[HermesKanbanTask], KanbanCommandError>]
    init(tasks: [HermesKanbanTask]) { taskResults = [.success(tasks)] }
    init(taskResults: [Result<[HermesKanbanTask], KanbanCommandError>]) { self.taskResults = taskResults }
    func listTasks() async throws -> [HermesKanbanTask] { try taskResults.removeFirst().get() }
    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail { throw KanbanCommandError.failed(command: "show", exitCode: 1, stderr: "unused") }
    func runs(taskID: String) async throws -> [HermesKanbanRun] { [] }
    func log(taskID: String, tailBytes: Int) async throws -> String { "" }
    func isAvailable() async -> Bool { true }
    func profileExists(_ profile: String) async -> Bool { true }
    func isGatewayRunning() async -> Bool { true }
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask { .fixture(id: "t_created", request: request) }
    func reclaim(taskID: String, reason: String) async throws {}
    func block(taskID: String, reason: String) async throws {}
    func unblock(taskID: String, reason: String) async throws {}
}

private actor ViewModelCoordinatorStub: KanbanWorkflowCoordinating {
    private var value: [KanbanWorkflow]
    private(set) var startCalls = 0
    init(workflows: [KanbanWorkflow]) { value = workflows }
    func workflows() async throws -> [KanbanWorkflow] { value }
    func createDraft(_ input: KanbanDraftInput) async throws -> KanbanWorkflow { value[0] }
    func start(workflowID: UUID) async throws -> KanbanWorkflow { startCalls += 1; return value[0] }
    func refresh() async throws -> [KanbanWorkflow] { value }
    func approve(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func cancel(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func retry(workflowID: UUID) async throws -> KanbanWorkflow { value[0] }
    func resumePendingTransitions() async throws -> [KanbanWorkflow] { value }
}

private extension HermesKanbanTask {
    static func fixture(id: String, request: HermesTaskCreateRequest) -> Self {
        .init(
            id: id, title: request.title, body: request.body,
            assignee: request.assignee, status: .ready, priority: request.priority,
            tenant: nil, workspaceKind: "dir", workspacePath: request.workspacePath,
            branchName: nil, projectID: nil, createdBy: "opshub",
            createdAt: 1, startedAt: nil, completedAt: nil, result: nil
        )
    }
}

private func makeTriageWorkflow() -> KanbanWorkflow {
    .init(
        schemaVersion: 1,
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        title: "Task",
        objective: "Objective",
        acceptanceCriteria: ["Criterion"],
        workspacePath: "/tmp/repo",
        priority: .normal,
        phase: .triage,
        currentStage: nil,
        repairCount: 0,
        stageReferences: [],
        pendingTransition: nil,
        cancellationReason: nil,
        createdAt: Date(timeIntervalSince1970: 1),
        updatedAt: Date(timeIntervalSince1970: 1)
    )
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter KanbanViewModelTests`

Expected: FAIL because the old view model only reads SQLite tasks.

- [ ] **Step 3: Implement CLI-backed refresh and ownership merge**

Replace `KanbanDatabaseReading` dependency with Hermes service + coordinator. Build one logical card per workflow; hide its internal stage task IDs from external cards. Remaining Hermes tasks are external and read-only for workflow actions.

Use these presentation types:

```swift
enum KanbanCardID: Hashable, Sendable {
    case workflow(UUID)
    case hermes(String)
}

enum KanbanAvailableAction: Hashable, Sendable {
    case start, approve, cancel, retry
}

struct KanbanCardViewData: Identifiable, Equatable, Sendable {
    let id: KanbanCardID
    let title: String
    let column: KanbanColumn
    let priority: KanbanPriority
    let displayID: String
    let workspacePath: String?
    let stageLabel: String?
    let elapsed: TimeInterval?
    let isWorkflowOwned: Bool
    let availableActions: Set<KanbanAvailableAction>

    var workspaceName: String? {
        workspacePath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }
}

struct KanbanBoardSnapshot: Equatable, Sendable {
    let cards: [KanbanCardViewData]
    let loadedAt: Date
}
```

Expose:

```swift
@Published private(set) var snapshot: KanbanBoardSnapshot?
@Published private(set) var isRefreshing = false
@Published private(set) var activeAction: KanbanAction?
@Published var selectedCardID: KanbanCardID?
@Published var isPresentingNewTask = false

func createDraft(_ input: KanbanDraftInput) async
func startSelected() async
func approveSelected() async
func cancelSelected() async
func retrySelected() async
func loadSelectedDetail() async
func loadSelectedLog(tailBytes: Int = 64_000) async
func autoRefresh() async
```

Guard every mutation with `activeAction == nil`, clear it in `defer`, and refresh only after successful mutation or partial-failure reconciliation.

`autoRefresh()` first calls `resumePendingTransitions()`, then refreshes immediately and every five seconds while `Task.isCancelled == false`. Use `try await Task.sleep(for: .seconds(5))`; exit cleanly on cancellation. Keep the existing SwiftUI `.task { await model.autoRefresh() }` lifecycle so leaving Kanban cancels polling. Add a test with an injected sleeper/clock proving cancellation stops further list calls and that the `refreshing` guard prevents overlapping polls.

- [ ] **Step 4: Add action-gating and external-task tests**

Verify:

- double Start invokes coordinator once;
- external task exposes detail/log but no Start/Approve/Cancel/Retry;
- task in Triage exposes only Start;
- Approval Required exposes approve/cancel;
- blocked recoverable exposes Retry;
- selected detail refresh does not clear board scroll identity.

- [ ] **Step 5: Run ViewModel and existing Kanban tests**

Run: `swift test --filter KanbanViewModelTests && swift test --filter KanbanSQLiteReaderTests`

Expected: new ViewModel tests PASS; existing SQLite tests still PASS temporarily until Task 10 retires them.

- [ ] **Step 6: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/ViewModels/KanbanViewModel.swift Sources/OpsHub/Features/Kanban/Models/KanbanModels.swift Tests/OpsHubTests/KanbanViewModelTests.swift Tests/OpsHubTests/KanbanTests.swift
git commit -m "feat: drive Kanban board from Hermes CLI"
```

### Task 8: Feature Header, Collapsible Columns, and Cards

**Files:**
- Modify: `Sources/OpsHub/Features/Kanban/Views/KanbanView.swift`
- Create: `Sources/OpsHub/Features/Kanban/Views/KanbanColumnView.swift`
- Modify: `Sources/OpsHub/Features/Kanban/Services/KanbanColumnPreferences.swift`
- Create: `Tests/OpsHubTests/KanbanViewTests.swift`

**Interfaces:**
- Consumes: `KanbanViewModel`, `KanbanColumnPreferences`, `OpsHubFeatureHeader`, `OpsHubTerminalTheme`.
- Produces: stable six-column board and testable layout/presentation policies.

- [ ] **Step 1: Write failing presentation-policy tests**

```swift
func testCollapsedColumnKeepsCompactWidthAndCount() {
    XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: true), 48)
    XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: false), 264)
}

func testCardPresentationShowsWorkspaceBasename() {
    let value = KanbanCardViewData(
        id: .hermes("t_1"),
        title: "Task",
        column: .ready,
        priority: .normal,
        displayID: "t_1",
        workspacePath: "/Users/me/opshub",
        stageLabel: nil,
        elapsed: nil,
        isWorkflowOwned: false,
        availableActions: []
    )
    XCTAssertEqual(value.workspaceName, "opshub")
}

enum KanbanColumnLayout {
    static func width(isCollapsed: Bool) -> CGFloat { isCollapsed ? 48 : 264 }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter KanbanViewTests`

Expected: FAIL because layout helpers and views do not exist.

- [ ] **Step 3: Replace the ad-hoc title row with the shared feature header**

```swift
OpsHubFeatureHeader(
    eyebrow: "OPSHUB / KANBAN",
    title: "Kanban",
    metadata: model.headerMetadata
) {
    HStack(spacing: 8) {
        Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
        Button("New Task", systemImage: "plus") { model.isPresentingNewTask = true }
            .keyboardShortcut("n", modifiers: .command)
    }
    .buttonStyle(.plain)
}
```

Keep New Task in the header; no create control may live in the horizontally scrolling board.

- [ ] **Step 4: Implement manual collapsed columns**

`KanbanColumnView` receives column, cards, collapsed flag and toggle closure. Collapsed width is `48`, expanded width is `264`. Collapsed state always renders title, count and semantic warning color. Do not auto-collapse empty columns and do not implement single-column focus mode.

- [ ] **Step 5: Implement compact cards without mutation buttons**

Card shows priority, logical/external task ID, title, current stage/assignee + elapsed time and workspace basename. The entire card is a plain button that selects it; Start/Cancel/Retry never appear on the card.

- [ ] **Step 6: Run view tests and focused build**

Run: `swift test --filter KanbanViewTests && swift build`

Expected: PASS; header adapts through `ViewThatFits`; six columns remain horizontally scrollable.

- [ ] **Step 7: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Views/KanbanView.swift Sources/OpsHub/Features/Kanban/Views/KanbanColumnView.swift Sources/OpsHub/Features/Kanban/Services/KanbanColumnPreferences.swift Tests/OpsHubTests/KanbanViewTests.swift
git commit -m "feat: add interactive Kanban board layout"
```

### Task 9: New Task Sheet and Right Inspector

**Files:**
- Create: `Sources/OpsHub/Features/Kanban/Views/KanbanNewTaskSheet.swift`
- Create: `Sources/OpsHub/Features/Kanban/Views/KanbanTaskInspector.swift`
- Modify: `Sources/OpsHub/Features/Kanban/Views/KanbanView.swift`
- Modify: `Tests/OpsHubTests/KanbanViewTests.swift`
- Modify: `Tests/OpsHubTests/KanbanViewModelTests.swift`

**Interfaces:**
- Consumes: ViewModel draft/action/detail/log methods and `KanbanWorkspaceValidating` validation result.
- Produces: validated task sheet, Inspector tabs, action routing, accessibility focus and log-follow policy.

- [ ] **Step 1: Write failing form and Inspector policy tests**

```swift
func testDraftFormRequiresStructuredFieldsAndValidRepository() {
    var state = KanbanDraftFormState()
    XCTAssertFalse(state.canSubmit)
    state.title = "Add report API"
    state.objective = "Export the filtered report"
    state.acceptanceCriteriaText = "Returns CSV\nKeeps existing filters"
    state.workspacePath = "/repo"
    state.validatedWorkspacePath = "/repo"
    XCTAssertTrue(state.canSubmit)
}

func testLiveLogFollowsOnlyWhenAlreadyAtBottom() {
    XCTAssertTrue(KanbanLogFollowPolicy.shouldFollow(distanceFromBottom: 4))
    XCTAssertFalse(KanbanLogFollowPolicy.shouldFollow(distanceFromBottom: 80))
}

struct KanbanDraftFormState: Equatable {
    var title = ""
    var objective = ""
    var acceptanceCriteriaText = ""
    var workspacePath = ""
    var validatedWorkspacePath: String?
    var priority: KanbanPriority = .normal

    var acceptanceCriteria: [String] {
        acceptanceCriteriaText.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canSubmit: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !acceptanceCriteria.isEmpty
            && validatedWorkspacePath == workspacePath
    }
}

enum KanbanLogFollowPolicy {
    static let threshold: CGFloat = 24
    static func shouldFollow(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= threshold
    }
}
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `swift test --filter KanbanViewTests`

Expected: FAIL because form and Inspector policies do not exist.

- [ ] **Step 3: Implement New Task sheet**

Fields are exactly Title, Objective, Acceptance Criteria, Workspace Path and Priority. Browse uses `NSOpenPanel` configured for one directory. Changing path invalidates `validatedWorkspacePath`; validation runs again through the view model. On success, replace `workspacePath` with the returned canonical path and set `validatedWorkspacePath` to the same value. `Create Task` is disabled until structured fields are nonempty and the current path matches that validated canonical path. Submit creates Triage only; do not add Create & Start.

- [ ] **Step 4: Implement right Inspector overlay and focus restoration**

Use a layout helper matching existing Inspector conventions: preferred width `460`, horizontal inset `16`. Tabs are Overview, Runs and Live Log. On appear, focus the heading; Escape/× closes; `KanbanInspectorFocusRouter` returns focus to the previously selected visible card.

Contextual actions:

```swift
HStack {
    if card.availableActions.contains(.start) {
        Button("Start") { Task { await model.startSelected() } }
    }
    if card.availableActions.contains(.approve) {
        Button("Approve & Continue") { Task { await model.approveSelected() } }
    }
    if card.availableActions.contains(.retry) {
        Button("Retry") { Task { await model.retrySelected() } }
    }
    if card.availableActions.contains(.cancel) {
        Button("Cancel Run", role: .destructive) { Task { await model.cancelSelected() } }
    }
}
```

Approval Required renders both approve and cancel. External tasks render no workflow mutation actions.

- [ ] **Step 5: Implement Runs and Live Log behavior**

Runs display outcome, role, elapsed time, summary and error per attempt. Live Log polls only while the tab and Inspector are visible, cancels on close, and auto-scrolls only when `KanbanLogFollowPolicy` says the reader was already at the bottom. Swift task cancellation must not call Hermes reclaim.

- [ ] **Step 6: Add accessibility and Reduce Motion tests**

Verify close callbacks, focus router, narrow Inspector placement, action labels, and overlay transition policy. Reduce Motion uses fade-only; normal mode uses right-edge slide + fade without moving the board surface.

Run: `swift test --filter KanbanViewTests && swift test --filter KanbanViewModelTests && swift build`

Expected: PASS.

- [ ] **Step 7: Record the commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban/Views/KanbanNewTaskSheet.swift Sources/OpsHub/Features/Kanban/Views/KanbanTaskInspector.swift Sources/OpsHub/Features/Kanban/Views/KanbanView.swift Tests/OpsHubTests/KanbanViewTests.swift Tests/OpsHubTests/KanbanViewModelTests.swift
git commit -m "feat: add Kanban task creation and inspector"
```

### Task 10: Retire SQLite Runtime Path and Complete Verification

**Files:**
- Delete: `Sources/OpsHub/Features/Kanban/Services/KanbanSQLiteReader.swift`
- Modify or delete: `Tests/OpsHubTests/KanbanTests.swift`
- Modify: `README.md` only if it currently documents direct SQLite reading; otherwise leave it unchanged.
- Verify: all Kanban source/test files from Tasks 1–9.

**Interfaces:**
- Consumes: passing CLI service, coordinator, ViewModel and UI tests.
- Produces: one runtime data path through Hermes CLI and final release-ready verification evidence.

- [ ] **Step 1: Prove no runtime consumer uses SQLite reader**

Run:

```bash
rg -n "KanbanSQLiteReader|KanbanDatabaseReading|SQLite3" Sources/OpsHub/Features/Kanban Tests/OpsHubTests
```

Expected: only the old reader and old reader tests match; no ViewModel/View consumer remains.

- [ ] **Step 2: Remove the old reader and SQLite-only tests**

Delete the runtime reader and its path/open/WAL/schema tests only after the CLI fixture tests cover list/show/runs and ViewModel refresh. Preserve any test helpers still used by new tests by moving them to the owning test file.

- [ ] **Step 3: Run the focused Kanban suite**

Run: `swift test --filter Kanban`

Expected: PASS for domain, store, CLI service, validator, coordinator, ViewModel and UI policy suites.

- [ ] **Step 4: Run full verification gates**

Run:

```bash
swift test
swift build
swift build -c release
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 5: Perform fresh-bundle visual QA**

Run the newly built app, not an older installed bundle. Verify:

1. New Task is in the feature header and creates Triage only.
2. Invalid/non-Git path blocks Create; dirty repo blocks Start with changed files.
3. Stopped Gateway blocks Start without creating a Hermes task.
4. Every column collapses manually, preserves count/warning color and restores after relaunch.
5. Card selection opens right Inspector without losing board scroll position.
6. Overview/Runs/Live Log load; log does not pull the reader back to bottom after manual scrolling.
7. Approval Required exposes approve/cancel; Running exposes cancel; Blocked exposes retry.
8. App relaunch reconciles an active workflow without duplicate stage creation.

- [ ] **Step 6: Inspect final scope and side effects**

Run:

```bash
git status --short
git diff --stat
git diff --check
```

Confirm there are no changes to GitLab, Brew, packaging, signing, release, Cask, secrets, `.hermes` data or the pre-existing `.superpowers/brainstorm/3275-1785750842/` artifact.

- [ ] **Step 7: Record the final commit checkpoint**

If authorized:

```bash
git add Sources/OpsHub/Features/Kanban Tests/OpsHubTests docs/superpowers/specs/2026-08-03-kanban-task-orchestration-design.md docs/superpowers/plans/2026-08-03-kanban-task-orchestration.md
git commit -m "feat: orchestrate Hermes tasks from Kanban"
```
