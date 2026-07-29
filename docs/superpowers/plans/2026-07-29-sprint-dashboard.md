# Sprint Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Dashboard placeholder with a read-only GitLab sprint dashboard driven by weekly milestones, member delivery counts, release labels, and production bugs created inside the sprint dates.

**Architecture:** Add a Dashboard-specific domain model and pure aggregator, expose narrowly scoped milestone/issue queries through `SprintDashboardServicing`, and let a dedicated `SprintDashboardViewModel` own milestone selection plus partial/stale loading states. Keep the existing GitLab tabs untouched and wire the new ViewModel into `ContentView` with the same selected-member settings used by Dev Room.

**Tech Stack:** Swift 6, SwiftUI on macOS 14, Foundation concurrency, GitLab REST API v4, XCTest.

## Global Constraints

- Use `GitLabWorkflowProject.path`; do not add a Project picker.
- Sprint dates come from milestone `start_date` Wednesday through `due_date` Tuesday, interpreted in `Asia/Ho_Chi_Minh`.
- `Released` requires normalized labels `Passed`, `ToProduction`, and `Merged`.
- Production bugs require normalized label `Bug Production` plus `created_at` inside the sprint dates; milestone and assignee do not affect this count.
- Member breakdown uses the first current assignee and the Dev Room selected-member IDs; unassigned issues get a final `Unassigned` row.
- Dashboard remains read-only and must not create or mutate milestones/issues.
- Preserve existing GitLab Overview/Issues/MR/Review/Pipeline behavior.
- Reuse `OpsHubTerminalTheme`; do not hardcode production colors from the HTML mockup.
- Do not add dependencies, run packaging, commit, push, open a PR, or create a release.

---

## File Map

- Create `Sources/OpsHub/Features/Dashboard/Models/SprintDashboardModels.swift`: milestone/member/issue/presentation models, date boundary logic, label rules, pure aggregation.
- Create `Sources/OpsHub/Features/Dashboard/Services/SprintDashboardServices.swift`: `SprintDashboardServicing` protocol only.
- Create `Sources/OpsHub/Features/Dashboard/ViewModels/SprintDashboardViewModel.swift`: selection, loading, refresh, cancellation generation, partial/stale state.
- Modify `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`: conform `GitLabService` to the Dashboard protocol and add three paginated project requests.
- Modify `Sources/OpsHub/Features/GitLab/Models/GitLabRESTModels.swift`: no schema redesign; keep using `GitLabMilestone`, `GitLabRESTIssue`, and `GitLabUser`.
- Modify `Sources/OpsHub/Shared/Components/DashboardView.swift`: replace placeholder with the approved Sprint Dashboard layout and focused subviews.
- Modify `Sources/OpsHub/App/ContentView.swift`: create/retain the Dashboard ViewModel, pass it to `DashboardView`, and propagate member-setting changes.
- Create `Tests/OpsHubTests/SprintDashboardAggregationTests.swift`: sprint/date/label/grouping regression tests.
- Create `Tests/OpsHubTests/SprintDashboardViewModelTests.swift`: lifecycle, selection, partial failure, stale data, and selected-member tests.
- Modify `Tests/OpsHubTests/GitLabServiceTests.swift`: exact Dashboard request/mapping/pagination tests.

---

### Task 1: Sprint Domain Models and Aggregator

**Files:**
- Create: `Sources/OpsHub/Features/Dashboard/Models/SprintDashboardModels.swift`
- Create: `Tests/OpsHubTests/SprintDashboardAggregationTests.swift`

**Interfaces:**
- Produces:
  - `SprintMilestone`
  - `SprintDashboardMember`
  - `SprintDashboardIssue`
  - `SprintDashboardMemberSummary`
  - `SprintDashboardData`
  - `SprintDashboardAggregator.currentMilestone(from:now:calendar:)`
  - `SprintDashboardAggregator.makeData(milestone:sprintIssues:productionBugs:selectedUserIDs:calendar:)`
- Consumes: Foundation `Calendar`, `Date`, `TimeZone`, and `URL`.

- [ ] **Step 1: Write failing tests for milestone selection and Vietnam date boundaries**

Add tests with a Gregorian calendar configured to `Asia/Ho_Chi_Minh`:

```swift
func testCurrentMilestoneUsesInclusiveVietnamDateBoundary() {
    let milestone = makeMilestone(
        id: 31,
        start: "2026-07-29T00:00:00+07:00",
        due: "2026-08-04T00:00:00+07:00"
    )

    XCTAssertEqual(
        SprintDashboardAggregator.currentMilestone(
            from: [milestone],
            now: date("2026-08-04T23:59:59+07:00"),
            calendar: vietnamCalendar
        )?.id,
        31
    )
}

func testCurrentMilestoneChoosesLatestStartThenLargestIDWhenRangesOverlap() {
    let older = makeMilestone(id: 30, start: "2026-07-22T00:00:00+07:00", due: "2026-08-04T00:00:00+07:00")
    let newer = makeMilestone(id: 31, start: "2026-07-29T00:00:00+07:00", due: "2026-08-04T00:00:00+07:00")
    XCTAssertEqual(
        SprintDashboardAggregator.currentMilestone(
            from: [older, newer],
            now: date("2026-07-30T12:00:00+07:00"),
            calendar: vietnamCalendar
        )?.id,
        31
    )
}
```

- [ ] **Step 2: Run the focused tests and confirm the new types do not exist**

Run:

```bash
swift test --filter SprintDashboardAggregationTests
```

Expected: build failure for missing `SprintMilestone` / `SprintDashboardAggregator`.

- [ ] **Step 3: Add the minimal domain types and sprint boundary helpers**

Implement these stable contracts:

```swift
struct SprintMilestone: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let startDate: Date
    let dueDate: Date
}

struct SprintDashboardMember: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let username: String?
    let avatarURL: URL?
}

struct SprintDashboardIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let project: String
    let labels: [String]
    let assignee: SprintDashboardMember?
    let createdAt: Date?
    let updatedAt: Date?
    let webURL: URL?
}
```

Use `calendar.startOfDay(for:)` for the start and `calendar.date(byAdding: .day, value: 1, to: startOfDueDate)` as an exclusive upper bound. A date belongs to the sprint when `createdAt >= start && createdAt < endExclusive`.

- [ ] **Step 4: Write failing aggregation tests**

Cover all business rules explicitly:

```swift
func testAggregationCountsReleaseOnlyWithAllThreeNormalizedLabels() {
    let issues = [
        issue(id: 1, labels: [" Passed ", "TOPRODUCTION", "merged"], assignee: alice),
        issue(id: 2, labels: ["Passed", "ToProduction"], assignee: alice)
    ]
    let data = SprintDashboardAggregator.makeData(
        milestone: milestone,
        sprintIssues: issues,
        productionBugs: [],
        selectedUserIDs: [alice.id],
        calendar: vietnamCalendar
    )
    XCTAssertEqual(data.ticketCount, 2)
    XCTAssertEqual(data.releasedCount, 1)
    XCTAssertEqual(data.memberSummaries.first?.releasedCount, 1)
}

func testProductionBugCountIgnoresMilestoneAndAssigneeButFiltersLabelAndCreatedAt() {
    // Include Bug Production exactly at sprint start and before endExclusive.
    // Exclude a regular Bug and an item at endExclusive.
}

func testMemberBreakdownUsesSelectedCurrentAssigneeAndKeepsUnassignedLast() {
    // Alice row + Unassigned row; omit an issue assigned to unselected Bob.
}

func testDuplicateGlobalIssueIDCountsOnceUsingNewestUpdatedIssue() {
    // Two versions of one issue must produce one ticket using the latest updatedAt.
}
```

- [ ] **Step 5: Implement pure aggregation**

Implement:

```swift
struct SprintDashboardMemberSummary: Identifiable, Hashable, Sendable {
    let member: SprintDashboardMember?
    let ticketCount: Int
    let releasedCount: Int
    var id: String { member.map { "member:\($0.id)" } ?? "unassigned" }
}

struct SprintDashboardData: Equatable, Sendable {
    let milestone: SprintMilestone
    let ticketCount: Int
    let releasedCount: Int
    let productionBugCount: Int
    let memberSummaries: [SprintDashboardMemberSummary]
    let productionBugPreview: [SprintDashboardIssue]
}
```

Aggregator rules:

- dedupe sprint issues and bug issues by global `id`, preferring newest `updatedAt`, keeping the first when timestamps tie;
- normalize label with trim + lowercase;
- release is an AND across `passed`, `toproduction`, `merged`;
- production bug requires `bug production` plus a valid `createdAt` inside the milestone boundary;
- KPI ticket/release counts use all milestone issues;
- member rows include selected IDs plus `Unassigned`, omit unselected assignees;
- sort members by case-insensitive name then ID, place `Unassigned` last;
- sort bug preview by `createdAt` descending then ID descending and keep `prefix(5)`.

- [ ] **Step 6: Run aggregation tests**

Run:

```bash
swift test --filter SprintDashboardAggregationTests
```

Expected: all tests pass.

---

### Task 2: GitLab Milestone and Sprint Issue Queries

**Files:**
- Create: `Sources/OpsHub/Features/Dashboard/Services/SprintDashboardServices.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Test: `Tests/OpsHubTests/GitLabServiceTests.swift`

**Interfaces:**
- Consumes domain types from Task 1.
- Produces:

```swift
protocol SprintDashboardServicing: Sendable {
    func sprintMilestones(projectPath: String) async throws -> [SprintMilestone]
    func sprintIssues(projectPath: String, milestoneTitle: String) async throws -> [SprintDashboardIssue]
    func productionBugs(
        projectPath: String,
        createdAfter: Date,
        createdBefore: Date
    ) async throws -> [SprintDashboardIssue]
}
```

- [ ] **Step 1: Add the protocol and failing service request tests**

Add tests that call the three methods on `GitLabService` and assert:

```swift
XCTAssertEqual(request.url?.percentEncodedPath, "/api/v4/projects/social%2Fsocom-issues/milestones")
XCTAssertEqual(query["order_by"], "due_date")
XCTAssertEqual(query["sort"], "desc")
XCTAssertEqual(query["per_page"], "100")
```

Sprint issue query must contain:

```text
state=all
milestone=Sprint 2026-W31
with_labels_details=true
per_page=100
```

Production bug query must contain:

```text
state=all
labels=Bug Production
created_after=<ISO-8601 UTC>
created_before=<ISO-8601 UTC>
with_labels_details=true
per_page=100
```

Also assert neither issue request contains `scope` nor `updated_after`.

- [ ] **Step 2: Run the service tests and verify failure**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: build failure because `GitLabService` does not conform to `SprintDashboardServicing`.

- [ ] **Step 3: Implement milestone loading and mapping**

Extend the conformance:

```swift
struct GitLabService:
    GitLabServicing,
    DevRoomServicing,
    DevRoomMemberServicing,
    SprintDashboardServicing,
    @unchecked Sendable
```

Request `projects/{encodedProject}/milestones` with `order_by=due_date`, `sort=desc`, `per_page=100` and `sendAllPages`. Parse GitLab date-only strings using a `DateFormatter` with:

```swift
formatter.calendar = Calendar(identifier: .gregorian)
formatter.locale = Locale(identifier: "en_US_POSIX")
formatter.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
formatter.dateFormat = "yyyy-MM-dd"
```

Drop REST milestones missing title, start date, or due date. Sort due date descending, then ID descending.

- [ ] **Step 4: Implement sprint issue and production bug loading**

Reuse `makeProjectIssuesRequest(...)`, `sendAllPages(...)`, and existing ISO date formatting. Map the first `GitLabUser` assignee into `SprintDashboardMember`; map `createdAt`, `updatedAt`, references, labels, IID, and web URL into `SprintDashboardIssue`.

Use a private helper:

```swift
private func mapSprintDashboardIssue(_ issue: GitLabRESTIssue) -> SprintDashboardIssue
```

- [ ] **Step 5: Add pagination and malformed milestone regression tests**

Prove:

- milestone `X-Next-Page` loads every page;
- sprint issue `X-Next-Page` loads every page;
- production bug `X-Next-Page` loads every page;
- a milestone missing `start_date`, `due_date`, or title is skipped without failing the response;
- `created_at` and first assignee are mapped.

- [ ] **Step 6: Run service and aggregation tests**

Run:

```bash
swift test --filter GitLabServiceTests
swift test --filter SprintDashboardAggregationTests
```

Expected: both suites pass.

---

### Task 3: Dashboard ViewModel Lifecycle and Partial Failures

**Files:**
- Create: `Sources/OpsHub/Features/Dashboard/ViewModels/SprintDashboardViewModel.swift`
- Create: `Tests/OpsHubTests/SprintDashboardViewModelTests.swift`

**Interfaces:**
- Consumes `SprintDashboardServicing` and `SprintDashboardAggregator`.
- Produces `SprintDashboardViewModel` for `DashboardView`.

- [ ] **Step 1: Write failing initial-load and selection tests**

Use a deterministic stub service and `now` closure:

```swift
@MainActor
func testLoadSelectsMilestoneContainingTodayAndBuildsDashboardData() async {
    let service = StubSprintDashboardService(
        milestones: [currentMilestone, previousMilestone],
        sprintIssues: [ticket],
        productionBugs: [bug]
    )
    let viewModel = SprintDashboardViewModel(
        service: service,
        selectedUserIDs: [alice.id],
        now: { self.date("2026-07-30T10:00:00+07:00") }
    )

    await viewModel.loadIfNeeded()

    XCTAssertEqual(viewModel.selectedMilestoneID, currentMilestone.id)
    XCTAssertEqual(viewModel.data?.ticketCount, 1)
    XCTAssertEqual(viewModel.data?.productionBugCount, 1)
}
```

Also test:

- no current milestone leaves metrics empty but milestone picker available;
- selecting another milestone reloads its issue/bug data;
- applying selected user IDs recomputes member rows without another service call.

- [ ] **Step 2: Define loading-state contracts and run tests**

Use:

```swift
enum SprintDashboardSectionState: Equatable {
    case idle
    case loading
    case loaded
    case stale(String)
    case failed(String)
}
```

Published properties:

```swift
@Published private(set) var milestones: [SprintMilestone] = []
@Published var selectedMilestoneID: Int?
@Published private(set) var data: SprintDashboardData?
@Published private(set) var milestoneState: SprintDashboardSectionState = .idle
@Published private(set) var deliveryState: SprintDashboardSectionState = .idle
@Published private(set) var bugState: SprintDashboardSectionState = .idle
@Published private(set) var lastUpdated: Date?
@Published private(set) var selectedUserIDs: Set<Int>
```

Run:

```bash
swift test --filter SprintDashboardViewModelTests
```

Expected: failure for the missing ViewModel.

- [ ] **Step 3: Implement initial loading and refresh**

Implement:

- `loadIfNeeded()`;
- `refresh()`;
- `selectMilestone(id:)`;
- `applySelectedUserIDs(_:)`;
- `autoRefresh(every:)` with `autoRefreshInterval = .seconds(5 * 60)`.

Keep raw sprint issues and bugs privately so member settings can re-aggregate without refetching.

- [ ] **Step 4: Write failing partial/stale/race tests**

Cover:

```swift
func testBugFailureKeepsLoadedDeliveryAndMarksOnlyBugFailed() async
func testRefreshFailureKeepsPreviousDataAndMarksSectionStale() async
func testOlderMilestoneResponseCannotReplaceNewSelection() async
func testConcurrentRefreshIsIgnored() async
func testCancellationRestoresPreviousState() async
```

- [ ] **Step 5: Implement independent section results and generation guard**

Load sprint issues and bugs concurrently, convert each operation to `Result`, and apply independently. Increment an integer generation whenever milestone selection changes; before publishing results, verify the captured generation and selected milestone ID still match.

Do not replace a successful value with zero on failure. Preserve the prior section data and use `.stale(message)` after a refresh failure; use `.failed(message)` when no successful value exists.

- [ ] **Step 6: Run ViewModel tests**

Run:

```bash
swift test --filter SprintDashboardViewModelTests
```

Expected: all tests pass.

---

### Task 4: Approved SwiftUI Dashboard and App Integration

**Files:**
- Modify: `Sources/OpsHub/Shared/Components/DashboardView.swift`
- Modify: `Sources/OpsHub/App/ContentView.swift`
- Test: `Tests/OpsHubTests/SprintDashboardViewModelTests.swift`

**Interfaces:**
- Consumes `SprintDashboardViewModel`.
- Preserves `DashboardView(viewModel:)` as the app entry view and provides a self-contained preview stub.

- [ ] **Step 1: Wire member-setting propagation explicitly**

Keep the two updates adjacent in the existing Settings save callback:

```swift
devRoomViewModel.applySelectedUserIDs(ids)
sprintDashboardViewModel.applySelectedUserIDs(ids)
```

The re-aggregation behavior of `applySelectedUserIDs(_:)` is covered by `SprintDashboardViewModelTests`; `ContentView` only forwards the same IDs already persisted by Settings.

- [ ] **Step 2: Replace the Dashboard placeholder with the approved hierarchy**

Build focused private subviews in `DashboardView.swift`:

```text
DashboardView
  ├─ SprintDashboardHeader
  ├─ SprintMetricGrid
  │    └─ SprintMetricCard × 3
  ├─ SprintMemberProgressTable
  └─ SprintProductionBugList
```

Approved content order:

1. dark/terminal-integrated header;
2. equal cards `Sprint tickets`, `Released`, `New production bugs`;
3. full-width `Member progress`;
4. full-width production bug preview;
5. no `Sprint scope` panel.

Use adaptive grid behavior so the three KPI cards collapse vertically at narrow width.

- [ ] **Step 3: Implement exact member-table alignment and semantics**

- Member column: leading.
- `Tickets` header and values: centered.
- `Released` header and values: centered.
- Progress: fills remaining width.
- Numbers use `.monospacedDigit()`.
- `Unassigned` remains last.
- Progress accessibility value: `"<released> of <tickets> released, <percent> percent"`.

- [ ] **Step 4: Implement loading, empty, partial, stale, and retry states**

Requirements:

- initial load uses `ProgressView`, not an empty blank;
- refresh retains existing layout/data;
- no current milestone explains the missing active sprint and leaves picker usable;
- no configured members shows a Settings guidance state only in the member table;
- bug zero shows “No production bugs created in this sprint”;
- local section failures show a retry action without hiding successful sections;
- stale state displays a concise warning and keeps old values;
- Refresh is disabled while either data section is loading.

- [ ] **Step 5: Wire ContentView lifecycle**

Add:

```swift
@StateObject private var sprintDashboardViewModel: SprintDashboardViewModel
```

Initialize it with the existing `resolvedGitLabService` and `visibilityStore.load().selectedUserIDs`, then render:

```swift
case .dashboard:
    DashboardView(viewModel: sprintDashboardViewModel)
```

When settings save selected IDs, update both Dev Room and Dashboard ViewModels.

Use `.task` in `DashboardView` for `loadIfNeeded()` and a cancellation-aware auto-refresh task.

- [ ] **Step 6: Run focused Dashboard tests and debug build**

Run:

```bash
swift test --filter SprintDashboard
swift build
```

Expected: all focused tests and debug build pass.

---

### Task 5: Full Regression and Diff Review

**Files:**
- Review all files listed in the File Map.
- Do not modify unrelated user files.

**Interfaces:**
- Consumes the completed implementation from Tasks 1–4.
- Produces a verified, uncommitted working tree ready for user review.

- [ ] **Step 1: Run all tests**

Run:

```bash
swift test
```

Expected: complete suite passes.

- [ ] **Step 2: Run release build**

Run:

```bash
swift build -c release
```

Expected: release build succeeds.

- [ ] **Step 3: Check formatting and whitespace**

Run:

```bash
git diff --check
```

Expected: no output and exit code 0.

- [ ] **Step 4: Review scope**

Run:

```bash
git status --short
git diff --stat
git diff -- Sources/OpsHub Tests/OpsHubTests
```

Confirm:

- no changes to existing GitLab workflow semantics;
- no secrets or environment-specific values;
- no packaging/release changes;
- the temporary `.superpowers/brainstorm/` artifacts are not included in production scope;
- design and implementation plan files are the only documentation additions.

- [ ] **Step 5: Hand off without committing**

Report:

- implemented behavior;
- changed areas;
- focused/full test and build results;
- any residual limitation, especially first-assignee semantics and milestone discipline;
- explicitly state that no commit, push, PR, packaging, or release was performed.

---

### Task 6: Default App Navigation to Dashboard

**Files:**
- Modify: `Sources/OpsHub/App/ContentView.swift`
- Test: `Tests/OpsHubTests/AppSectionTests.swift`

**Interfaces:**
- Consumes: `AppNavigationState.selection: AppSection?`
- Produces: a new `AppNavigationState` initialized with `.dashboard`

- [ ] **Step 1: Write the failing regression test**

Add:

```swift
func testNavigationDefaultsToDashboard() {
    XCTAssertEqual(AppNavigationState().selection, .dashboard)
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter AppSectionTests/testNavigationDefaultsToDashboard
```

Expected: FAIL because the current selection is `.gitLab`.

- [ ] **Step 3: Apply the minimal implementation**

Change the initial selection:

```swift
@Published var selection: AppSection? = .dashboard
```

Do not persist or restore the previously selected section.

- [ ] **Step 4: Verify the focused and full suite**

Run:

```bash
swift test --filter AppSectionTests
swift test
swift build
git diff --check
```

Expected: all tests and the debug build pass; the diff check has no output.

- [ ] **Step 5: Hand off without committing**

Report the default-navigation behavior and verification results. Do not commit,
push, create a pull request, package, or release.
