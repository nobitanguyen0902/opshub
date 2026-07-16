# GitLab Auto Refresh and Sticky Refresh Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tự động làm mới dữ liệu GitLab mỗi 5 phút khi dashboard đang hiển thị và giữ nút Refresh luôn nhìn thấy, bấm được khi người dùng cuộn nội dung.

**Architecture:** Giữ nguyên `ContentView` sở hữu `GitLabDashboardViewModel` và toàn bộ service/load flow hiện tại. ViewModel cung cấp vòng lặp auto-refresh có thể hủy theo lifecycle của SwiftUI task; `GitLabDashboardView` đặt header ngoài `ScrollView` để các control không cuộn khỏi màn hình.

**Tech Stack:** Swift 6, SwiftUI, Swift Concurrency, XCTest, macOS 14.

## Global Constraints

- Chu kỳ auto refresh chính xác là 5 phút.
- Không tạo refresh song song cho cùng project scope; tiếp tục dùng guard `loadingScope` hiện tại.
- Auto refresh chỉ chạy khi GitLab dashboard đang hiển thị và tự dừng khi SwiftUI hủy task.
- Giữ nguyên kiến trúc, service contract, filter, selection và layout responsive hiện có.

---

### Task 1: Add cancellable five-minute auto refresh

**Files:**
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Test: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

**Interfaces:**
- Consumes: `GitLabDashboardViewModel.refresh() async` và guard `loadingScope` hiện có.
- Produces: `GitLabDashboardViewModel.autoRefresh(every:) async`, mặc định dùng `autoRefreshInterval = .seconds(300)`.

- [x] **Step 1: Write the failing auto-refresh test**

```swift
@MainActor
func testAutoRefreshLoadsAfterIntervalAndStopsWhenCancelled() async {
    let service = SlowCountingGitLabService(delay: .zero)
    let viewModel = GitLabDashboardViewModel(service: service)
    let autoRefreshTask = Task {
        await viewModel.autoRefresh(every: .milliseconds(100))
    }

    for _ in 0..<200 {
        if await service.callCount() > 0 { break }
        try? await Task.sleep(for: .milliseconds(1))
    }

    let callsAfterInterval = await service.callCount()
    XCTAssertGreaterThan(callsAfterInterval, 0)
    autoRefreshTask.cancel()
    await autoRefreshTask.value
    let callsAtCancellation = await service.callCount()
    try? await Task.sleep(for: .milliseconds(120))
    let callsAfterCancellation = await service.callCount()
    XCTAssertEqual(callsAfterCancellation, callsAtCancellation)
}
```

Update `SlowCountingGitLabService` so its delay is injectable:

```swift
private actor SlowCountingGitLabService: GitLabServicing {
    private let delay: Duration
    private(set) var mergeRequestCalls = 0

    init(delay: Duration = .milliseconds(50)) {
        self.delay = delay
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        mergeRequestCalls += 1
        try await Task.sleep(for: delay)
        return []
    }
}
```

- [x] **Step 2: Run the targeted test and verify it fails**

Run: `swift test --filter GitLabDashboardViewModelTests/testAutoRefreshLoadsAfterIntervalAndStopsWhenCancelled`

Expected: build fails because `autoRefresh(every:)` does not exist yet.

- [x] **Step 3: Implement the cancellable refresh loop**

Add to `GitLabDashboardViewModel`:

```swift
static let autoRefreshInterval: Duration = .seconds(5 * 60)

func autoRefresh(every interval: Duration = autoRefreshInterval) async {
    while Task.isCancelled == false {
        do {
            try await Task.sleep(for: interval)
        } catch {
            return
        }
        guard Task.isCancelled == false else { return }
        await refresh()
    }
}
```

Attach the loop to `GitLabDashboardView` so SwiftUI owns cancellation:

```swift
.task {
    await viewModel.autoRefresh()
}
```

- [x] **Step 4: Run the targeted tests**

Run: `swift test --filter GitLabDashboardViewModelTests`

Expected: all `GitLabDashboardViewModelTests` pass, including the new timer/cancellation regression.

### Task 2: Keep Refresh controls outside the scrolling content

**Files:**
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`

**Interfaces:**
- Consumes: existing `header(mode:)`, `GitLabAdaptiveLayout`, and `mode.pagePadding`.
- Produces: a fixed header region above the dashboard `ScrollView`; all navigation, metrics, warning, and section content remain scrollable.

- [x] **Step 1: Move the header outside `ScrollView` without changing its controls**

Replace the current adaptive layout body with:

```swift
GitLabAdaptiveLayout { mode in
    VStack(alignment: .leading, spacing: 0) {
        header(mode: mode)
            .padding(.horizontal, mode.pagePadding)
            .padding(.top, mode.pagePadding)

        ScrollView {
            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xLarge) {
                GitLabWorkspaceNavigation(
                    mode: mode,
                    selection: selectedSection,
                    badgeCount: viewModel.badgeCount
                )
                GitLabSummaryStrip(
                    metrics: viewModel.summaryMetrics,
                    mode: mode,
                    onSelect: viewModel.activate
                )
                warning
                sectionContent(mode: mode)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, mode.pagePadding)
            .padding(.top, GitLabDesignTokens.Spacing.xLarge)
            .padding(.bottom, mode.pagePadding)
        }
    }
}
```

- [x] **Step 2: Build and run the complete verification gate**

Run: `swift test`

Expected: all tests pass.

Run: `swift build`

Expected: debug build succeeds.

Run: `swift build -c release`

Expected: release build succeeds.

Run: `git diff --check`

Expected: no whitespace errors.

- [ ] **Step 3: Manually verify the UI behavior**

Run: `swift run OpsHub`, open GitLab, scroll each long section to the bottom, and confirm the header plus enabled Refresh button remain visible. Leave GitLab open for 5 minutes and confirm the timestamp/data refresh once without changing the selected section, search, filters, or selected project scope.
