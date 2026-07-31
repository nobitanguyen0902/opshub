# GitLab Pipeline Job Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep GitLab pipeline job details synchronized after a stage action and whenever the user refreshes the dashboard.

**Architecture:** Keep mutation state separate from lifecycle monitoring: lock a stage only while the GitLab mutation request is being submitted, then monitor its jobs with a replaceable per-stage token until a terminal state or a 30-minute bound. After the normal pipeline batch refresh, force-refresh only details already present in the view-model cache.

**Tech Stack:** Swift 6, Swift Concurrency, SwiftUI `ObservableObject`, XCTest

## Global Constraints

- Do not change GitLab REST endpoints or data contracts.
- Do not fetch jobs for pipelines that have never loaded details.
- Preserve the previous loaded detail snapshot when a detail refresh fails.
- Do not trigger real GitLab CI mutations during verification.
- Do not commit, push, or open a PR unless the user asks.

---

### Task 1: Poll a long-running stage through its terminal state

**Files:**
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift:238-370`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift:1-32,300-383,580-624`

**Interfaces:**
- Consumes: `perform(_:on:pipeline:pollIntervals:)`, `loadPipelineDetails(_:force:)`
- Produces: `pipelineActionPollIntervals: [Duration]`, `PipelineStageMonitor`, `pipelineStageMonitors: [GitLabPipelineStageKey: PipelineStageMonitor]`, and token-aware `monitor(stageName:pipeline:actionKey:monitorID:intervals:)`

- [ ] **Step 1: Add a regression stub whose job stays running before succeeding**

Extend `PipelineActionGitLabService` with an initializer accepting a post-play status sequence:

```swift
private actor PipelineActionGitLabService: GitLabServicing {
    private var pipelineJobsCalls = 0
    private var playJobIDs: [Int] = []
    private var postPlayStatuses: [GitLabJobStatus]

    init(postPlayStatuses: [GitLabJobStatus] = [.success]) {
        self.postPlayStatuses = postPlayStatuses
    }

    func pipelineJobs(projectID: Int, pipelineID: Int) async throws -> [GitLabJob] {
        pipelineJobsCalls += 1
        let status: GitLabJobStatus
        if playJobIDs.isEmpty {
            status = .manual
        } else if postPlayStatuses.count > 1 {
            status = postPlayStatuses.removeFirst()
        } else {
            status = postPlayStatuses.first ?? .success
        }
        return [makeActionJob(status: status)]
    }
}
```

Keep job construction actor-local because the existing test helper is instance-scoped on the test case.

- [ ] **Step 2: Add failing tests for the current lock duration and polling bound**

```swift
@MainActor
func testBuildStageUnlocksActionWhileRunningJobIsStillMonitored() async {
    let service = PipelineActionGitLabService(postPlayStatuses: [.running])
    let viewModel = GitLabDashboardViewModel(service: service)
    let pipeline = actionPipeline()
    let stage = GitLabPipelineStage(
        name: "deploy",
        jobs: [actionJob(status: .manual)]
    )

    let actionTask = Task {
        await viewModel.perform(
            .build,
            on: stage,
            pipeline: pipeline,
            pollIntervals: [.seconds(5)]
        )
    }
    for _ in 0..<100 {
        if await service.recordedCalls().pipelineJobs >= 2 { break }
        await Task.yield()
    }

    XCTAssertEqual(viewModel.stageActionState(for: stage, pipeline: pipeline), .idle)
    actionTask.cancel()
    await actionTask.value
}

@MainActor
func testDefaultPipelineActionPollingWindowIsThirtyMinutes() {
    let duration = GitLabDashboardViewModel.pipelineActionPollIntervals
        .reduce(Duration.zero, +)
    XCTAssertEqual(duration, .seconds(30 * 60))
}

@MainActor
func testBuildStageKeepsPollingUntilRunningJobSucceeds() async {
    let service = PipelineActionGitLabService(
        postPlayStatuses: [.running, .running, .success]
    )
    let viewModel = GitLabDashboardViewModel(service: service)
    let pipeline = actionPipeline()
    let stage = GitLabPipelineStage(
        name: "deploy",
        jobs: [actionJob(status: .manual)]
    )

    await viewModel.perform(
        .build,
        on: stage,
        pipeline: pipeline,
        pollIntervals: [.zero, .zero]
    )

    guard case let .loaded(details) = viewModel.pipelineDetailsState(for: pipeline) else {
        return XCTFail("Expected loaded pipeline details.")
    }
    XCTAssertEqual(details.stages.first?.status, .success)
    XCTAssertEqual(viewModel.pipelineActionNotice?.severity, .success)
    let calls = await service.recordedCalls()
    XCTAssertEqual(calls.pipelineJobs, 4)
}
```

- [ ] **Step 3: Run the regression test before production changes**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests/testBuildStageUnlocksActionWhileRunningJobIsStillMonitored
```

Expected: FAIL because the existing implementation keeps `.running(.build)` for the full monitoring loop; preserve the failure output as baseline evidence. The polling-window test also fails to compile until the explicit 30-minute schedule is added.

- [ ] **Step 4: Separate mutation locking from monitoring**

In `GitLabDashboardViewModel`:

```swift
static let pipelineActionPollIntervals: [Duration] =
    [.seconds(2), .seconds(3), .seconds(5)]
    + Array(repeating: .seconds(10), count: 179)

private struct PipelineStageMonitor {
    let id: UUID
    let task: Task<Void, Never>
}

private var pipelineStageMonitors: [GitLabPipelineStageKey: PipelineStageMonitor] = [:]
```

Change the public test seam to:

```swift
func perform(
    _ action: GitLabPipelineStageAction,
    on stage: GitLabPipelineStage,
    pipeline: GitLabPipeline,
    pollIntervals: [Duration]? = nil
) async
```

After all job mutations are accepted:

```swift
let acceptedDetails = GitLabPipelineDetails(
    pipeline: refreshedDetails.pipeline,
    jobs: freshJobs.map { acceptedJobsByID[$0.id] ?? $0 }
)
pipelineDetails[acceptedDetails.pipeline] = .loaded(acceptedDetails)
pipelineStageActions[actionKey] = .idle
let monitorID = UUID()
pipelineStageMonitors[actionKey]?.task.cancel()
let monitorTask = Task { [weak self] in
    guard let self else { return }
    await self.monitor(
        stageName: stage.name,
        pipeline: pipeline,
        actionKey: actionKey,
        monitorID: monitorID,
        intervals: pollIntervals ?? Self.pipelineActionPollIntervals
    )
}
pipelineStageMonitors[actionKey] = PipelineStageMonitor(id: monitorID, task: monitorTask)
await monitorTask.value
if pipelineStageMonitors[actionKey]?.id == monitorID {
    pipelineStageMonitors.removeValue(forKey: actionKey)
}
```

The monitor must check `pipelineStageMonitors[actionKey]?.id == monitorID` before each fetch and before publishing a terminal/timeout notice. A newer Build/Retry/Cancel action cancels and replaces the stored task, so the old monitor exits without overwriting newer state.

The mutation loop must store each returned `GitLabJob` in `acceptedJobsByID` so the stage changes from `Manual` to the accepted status before polling yields to the network.

- [ ] **Step 5: Add bounded timeout behavior**

After the polling loop exhausts while the same token is current, set:

```swift
pipelineActionNotice = GitLabPipelineActionNotice(
    message: "\(stageName) is still running. Refresh to check its latest status.",
    severity: .neutral
)
```

Keep the last successful `.loaded` details snapshot.

- [ ] **Step 6: Verify Task 1**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests
```

Expected: all dashboard view-model tests pass, including running → success, tag read-only, and unknown pipeline type.

---

### Task 2: Refresh details already loaded in the dashboard

**Files:**
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift:408-485`

**Interfaces:**
- Consumes: `pipelineDetails: [GitLabPipelineKey: GitLabPipelineDetailsLoadState]`, `loadPipelineDetails(_:force:)`
- Produces: `refreshLoadedPipelineDetails(_:) async` and `cancelMonitors(excluding:)`

- [ ] **Step 1: Add a refresh-specific actor stub**

```swift
private actor RefreshingPipelineGitLabService: GitLabServicing {
    private let pipeline: GitLabPipeline
    private var jobStatus: GitLabJobStatus = .running
    private var pipelineJobsCalls = 0

    init(pipeline: GitLabPipeline) {
        self.pipeline = pipeline
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] { [] }
    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [pipeline] }
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }

    func pipelineJobs(projectID: Int, pipelineID: Int) async throws -> [GitLabJob] {
        pipelineJobsCalls += 1
        return [GitLabJob(
            id: 301,
            name: "deploy-production",
            stage: "deploy",
            status: jobStatus,
            allowFailure: false,
            isArchived: false,
            failureReason: nil,
            duration: nil,
            webURL: nil
        )]
    }

    func setJobStatus(_ status: GitLabJobStatus) {
        jobStatus = status
    }

    func recordedPipelineJobsCalls() -> Int {
        pipelineJobsCalls
    }
}
```

- [ ] **Step 2: Add the failing Refresh regression test**

```swift
@MainActor
func testRefreshReloadsDetailsForPreviouslyLoadedPipeline() async {
    let pipeline = actionPipeline()
    let service = RefreshingPipelineGitLabService(pipeline: pipeline)
    let viewModel = GitLabDashboardViewModel(service: service)

    await viewModel.loadPipelineDetails(pipeline)
    await service.setJobStatus(.success)
    await viewModel.refresh()

    guard case let .loaded(details) = viewModel.pipelineDetailsState(for: pipeline) else {
        return XCTFail("Expected loaded pipeline details.")
    }
    XCTAssertEqual(details.stages.first?.status, .success)
    let calls = await service.recordedPipelineJobsCalls()
    XCTAssertEqual(calls, 2)
}
```

- [ ] **Step 3: Run the Refresh regression test before its fix**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests/testRefreshReloadsDetailsForPreviouslyLoadedPipeline
```

Expected: FAIL with stage status `Running` because `refresh()` currently preserves cached details without refetching jobs.

- [ ] **Step 4: Capture cached pipeline keys before applying the new batch**

Inside `refresh()`, before applying `pipelinesResult`, capture:

```swift
let loadedPipelineKeys = Set(pipelineDetails.keys)
var pipelinesWithLoadedDetails: [GitLabPipeline] = []
```

Inside the successful pipeline-batch assignment closure, derive pipelines whose keys were already loaded:

```swift
pipelinesWithLoadedDetails = batch.pipelines.filter {
    loadedPipelineKeys.contains(pipelineKey(for: $0))
}
```

Do not add never-expanded pipelines to this collection.

- [ ] **Step 5: Force-refresh only cached details**

Add:

```swift
private func refreshLoadedPipelineDetails(_ pipelines: [GitLabPipeline]) async {
    for pipeline in pipelines {
        await loadPipelineDetails(pipeline, force: true)
    }
}
```

Call it after the pipeline batch has been applied. `loadPipelineDetails` already preserves a previous `.loaded` state on errors, satisfying partial-failure behavior.

- [ ] **Step 6: Clean up monitors for pipelines no longer active**

After deriving `activeKeys`, remove monitor tasks whose `key.pipeline` is absent:

```swift
let obsoleteMonitorKeys = pipelineStageMonitors.keys.filter {
    !activeKeys.contains($0.pipeline)
}
for key in obsoleteMonitorKeys {
    pipelineStageMonitors[key]?.task.cancel()
    pipelineStageMonitors.removeValue(forKey: key)
}
```

Token removal causes any sleeping stale monitor to exit before its next fetch or notice update.

- [ ] **Step 7: Verify Task 2**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests/testRefreshReloadsDetailsForPreviouslyLoadedPipeline
swift test --filter GitLabDashboardViewModelTests
```

Expected: both commands pass.

---

### Task 3: Full verification and scope audit

**Files:**
- Verify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Verify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Verify: `docs/superpowers/specs/2026-07-31-gitlab-pipeline-job-refresh-design.md`
- Verify: `docs/superpowers/plans/2026-07-31-gitlab-pipeline-job-refresh.md`

**Interfaces:**
- Consumes: completed polling and refresh behavior
- Produces: verified, uncommitted working tree ready for user review

- [ ] **Step 1: Run the focused pipeline test family**

```bash
swift test --filter GitLabPipelineStageTests
swift test --filter GitLabDashboardViewModelTests
```

Expected: all focused tests pass.

- [ ] **Step 2: Run repository verification**

```bash
swift test
swift build
swift build -c release
git diff --check
```

Expected: tests, debug build, release build, and whitespace validation pass.

- [ ] **Step 3: Review the final diff**

```bash
git status --short
git diff --stat
git diff -- Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift Tests/OpsHubTests/GitLabDashboardViewModelTests.swift
```

Confirm no endpoint, model contract, unrelated UI, packaging, Cask, or release files changed. Leave all changes uncommitted.
