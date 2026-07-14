# GitLab Notification Removal and Screen Cache Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thực hiện ba Change Work Item bổ sung trên GitLab Workspace hiện tại: bỏ Notification Tab, bỏ Recent notifications và tránh gọi lại API khi mở lại màn hình GitLab với cùng project scope.

**Architecture:** Giữ nguyên luồng `GitLabService -> GitLabDashboardViewModel -> SwiftUI Views`. Dữ liệu notification vẫn được tải để phục vụ metric `Pending` và `Action queue`; chỉ destination và preview notification bị loại bỏ. Cache dùng chính dữ liệu đã có trong `GitLabDashboardViewModel`: nâng lifetime của ViewModel lên `ContentView` và ghi nhớ scope đã tải thành công, không thêm service/cache layer hoặc cơ chế persistence mới.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, Swift Package Manager, macOS 14+.

## Global Constraints

- Đây là Change Work Items trên implementation hiện tại; không tái tạo hoặc thay thế các Work Item trước.
- Trước khi execute plan, implementation hiện tại phải là baseline đã commit hoặc phải được mở trong worktree riêng; không commit lẫn các thay đổi đang staged của baseline vào Change Work Items.
- Không redesign UI; chỉ bỏ Notification Tab và Recent notifications theo yêu cầu.
- Không thay đổi spacing, typography, material, màu, breakpoint hoặc component list/row hiện có.
- Giữ notification API, `GitLabNotification`, metric `Pending` và notification-derived entries trong `Action queue`.
- Không thay đổi GitLab endpoint, request payload, authentication hoặc cách lưu personal access token.
- Cache chỉ có lifetime trong phiên chạy app, chỉ áp dụng cho scope đang hiển thị và không persist xuống disk/UserDefaults.
- Mở lại GitLab với cùng scope dùng dữ liệu hiện có; đổi scope vẫn fetch; nút Refresh luôn fetch.
- Initial load thất bại hoàn toàn không được đánh dấu là đã cache để lần mở sau có thể retry.
- Giữ nguyên partial-load, stale-data, duplicate-refresh guard, selection và filter behavior hiện tại.
- Không thêm dependency hoặc file cache mới.
- Mỗi task phải có test mục tiêu và `swift build`; CWI-01/CWI-02 dùng chung một commit vì xóa destination và xóa link preview là một thay đổi compile-coupled, CWI-03 dùng commit riêng.

## Target File Changes

```text
Sources/OpsHub/App/
└── ContentView.swift                                      # giữ ViewModel qua các lần đổi sidebar

Sources/OpsHub/Features/GitLab/
├── Components/
│   └── GitLabWorkspaceNavigation.swift                   # bỏ preview reference tới notifications
├── Models/
│   └── GitLabModels.swift                                # bỏ workspace destination/filter notification
├── ViewModels/
│   └── GitLabDashboardViewModel.swift                    # bỏ tab/preview state và thêm current-scope cache marker
└── Views/
    ├── GitLabDashboardView.swift                         # nhận ViewModel từ ContentView, bỏ notification route
    ├── GitLabNotificationsView.swift                     # xóa vì không còn destination
    └── GitLabOverviewView.swift                          # bỏ Recent notifications, giữ layout hiện tại với hai preview

Tests/OpsHubTests/
├── GitLabDashboardViewModelTests.swift                   # regression cho notification behavior và cache
└── GitLabWorkspaceStateTests.swift                       # section order mới

docs/
└── gitlab-workspace-verification.md                      # cập nhật checklist theo UI/cache mới
```

---

### Task 1: Remove Notification Tab and Recent Notifications Without Removing Notification Data

**Change Work Items:** CWI-01, CWI-02

**Files:**

- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift:4-30,207-217`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift:57-77,148-153,188-196,224-260,284-328`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift:74-166`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabOverviewView.swift:3-50`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceNavigation.swift:80-85`
- Delete: `Sources/OpsHub/Features/GitLab/Views/GitLabNotificationsView.swift`
- Test: `Tests/OpsHubTests/GitLabWorkspaceStateTests.swift:4-14`
- Test: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift:26-41,92-122`

**Interfaces:**

- Consumes: `GitLabNotification`, `GitLabActionQueueBuilder.build(...)`, `GitLabSummaryMetricKind.pendingNotifications`, `GitLabSectionLoadState`, và `GitLabDashboardViewModel.apply(...)` hiện có.
- Produces: `GitLabWorkspaceSection` chỉ còn `.overview`, `.mergeRequests`, `.reviews`, `.issues`, `.pipelines`; notification loading được theo dõi bằng state `.overview`; Overview chỉ còn hai preview cards.

- [ ] **Step 1: Update the workspace contract test first**

Thay assertion section order trong `GitLabWorkspaceStateTests` bằng:

```swift
func testWorkspaceSectionsHaveStableApprovedOrder() {
    XCTAssertEqual(
        GitLabWorkspaceSection.allCases,
        [.overview, .mergeRequests, .reviews, .issues, .pipelines]
    )
    XCTAssertEqual(
        GitLabWorkspaceSection.allCases.map(\.title),
        ["Overview", "Merge Requests", "Reviews", "Issues", "Pipelines"]
    )
}
```

- [ ] **Step 2: Add ViewModel regression assertions before production changes**

Trong `testRefreshKeepsLoadedSectionsWhenOneSectionFails`, thay notification section assertion bằng Overview state:

```swift
XCTAssertEqual(
    viewModel.loadState(for: .overview),
    .failed("GitLab request failed with status 403.")
)
XCTAssertEqual(
    viewModel.overviewLoadState,
    .stale("GitLab request failed with status 403.")
)
```

Thêm test giữ notification trong Overview behavior nhưng không điều hướng tới tab riêng:

```swift
@MainActor
func testPendingMetricKeepsUserOnOverviewAndNotificationsRemainInActionQueue() async {
    let viewModel = GitLabDashboardViewModel(service: StubGitLabService())
    await viewModel.refresh()
    viewModel.selectedSection = .pipelines

    viewModel.activate(.pendingNotifications)

    XCTAssertEqual(viewModel.selectedSection, .overview)
    XCTAssertTrue(viewModel.actionQueue.contains { $0.id == .notification(303) })
    XCTAssertEqual(
        viewModel.summaryMetrics.first { $0.kind == .pendingNotifications }?.value,
        1
    )
}
```

Trong `testOverviewSearchFiltersActionQueueAndPreviews`, giữ ba assertion còn có consumer và bỏ assertion `notificationPreview`:

```swift
XCTAssertEqual(viewModel.actionQueue.map(\.id), [.review(102)])
XCTAssertEqual(viewModel.mergeRequestPreview.map(\.id), [.mergeRequest(101)])
XCTAssertTrue(viewModel.pipelinePreview.isEmpty)
```

- [ ] **Step 3: Run the focused tests and confirm the contract fails against current code**

Run:

```bash
swift test --filter GitLabWorkspaceStateTests
swift test --filter GitLabDashboardViewModelTests
```

Expected:

- `GitLabWorkspaceStateTests` fails because `.notifications` is still in `allCases`.
- `GitLabDashboardViewModelTests` does not compile or fails because pending activation still selects `.notifications` and notification failure is still stored under `.notifications`.

- [ ] **Step 4: Remove notifications from the workspace destination enum**

Thay enum đầu file `GitLabModels.swift` bằng:

```swift
/// Top-level destinations inside the GitLab workspace.
enum GitLabWorkspaceSection: String, CaseIterable, Identifiable, Hashable, Sendable {
    case overview
    case mergeRequests
    case reviews
    case issues
    case pipelines

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
        }
    }
}
```

Xóa `GitLabWorkspaceFiltering.notifications(_:scope:filter:)` vì Notification Tab và notification filter không còn consumer. Không xóa `sortNotifications(_:)` nếu `GitLabActionQueueBuilder` hoặc test hiện tại vẫn tham chiếu; xác nhận bằng:

```bash
rg -n "GitLabWorkspaceFiltering\.(notifications|sortNotifications)" Sources Tests
```

Expected: không còn call tới `.notifications(...)`; chỉ giữ `sortNotifications` nếu kết quả `rg` còn consumer hợp lệ.

- [ ] **Step 5: Reuse Overview section state for notification loading**

Trong `GitLabDashboardViewModel`:

1. Đổi state collection của `overviewLoadState` để bao gồm `.overview`:

```swift
let states = GitLabWorkspaceSection.allCases.map(loadState)
```

2. Xóa toàn bộ computed properties `notificationPreview` và `visibleNotifications`.

3. Giữ `badgeCount(for:)` exhaustive với năm destinations:

```swift
func badgeCount(for section: GitLabWorkspaceSection) -> Int {
    switch section {
    case .overview:
        0
    case .mergeRequests:
        visibleMergeRequests.count
    case .reviews:
        visibleMergeReviews.count
    case .issues:
        visibleIssues.count
    case .pipelines:
        visiblePipelines.filter { $0.status == .failed }.count
    }
}
```

4. Thay pending metric activation bằng Overview:

```swift
case .pendingNotifications:
    selectedSection = .overview
    clearFilters(for: .overview)
```

5. Trong `refresh()`, thay notification loading state:

```swift
beginLoading(.overview, hasData: notifications.isEmpty == false)
```

6. Áp notification result vào Overview state nhưng vẫn assign mảng notification hiện có:

```swift
let notificationsSucceeded = apply(
    notificationsResult,
    section: .overview,
    hadData: notifications.isEmpty == false
) { notifications = $0 }
```

Giữ nguyên `notificationsTask`, `notificationsResult`, `loadWarning` input và `notificationsSucceeded` trong điều kiện cập nhật `lastUpdated` để `Pending` và `Action queue` tiếp tục dùng dữ liệu thật.

- [ ] **Step 6: Remove the Notification destination from dashboard rendering**

Trong `GitLabDashboardView`, thay Overview construction bằng:

```swift
GitLabOverviewView(
    mode: mode,
    actionQueue: viewModel.actionQueue,
    mergeRequests: viewModel.mergeRequestPreview,
    pipelines: viewModel.pipelinePreview,
    selectedItemID: viewModel.selection.item,
    loadState: viewModel.overviewLoadState,
    onSelect: viewModel.select,
    onShowSection: { viewModel.selectedSection = $0 },
    onRetry: refresh
)
```

Xóa toàn bộ branch sau khỏi `sectionContent(mode:)`:

```swift
case .notifications:
    GitLabNotificationsView(
        mode: mode,
        items: viewModel.visibleNotifications.map(GitLabWorkItemPresentation.init(notification:)),
        loadState: viewModel.loadState(for: .notifications),
        filter: viewModel.filter(for: .notifications),
        selectedItemID: viewModel.selection.item,
        onSelect: viewModel.select,
        onClearFilters: { viewModel.clearFilters(for: .notifications) },
        onRetry: refresh
    )
```

- [ ] **Step 7: Remove Recent notifications while preserving the existing responsive layout**

Trong `GitLabOverviewView`, xóa property:

```swift
let notifications: [GitLabWorkItemPresentation]
```

Thay `previewGrid` bằng đúng hai preview hiện hữu:

```swift
@ViewBuilder
private var previewGrid: some View {
    if mode == .wide {
        HStack(alignment: .top, spacing: GitLabDesignTokens.Spacing.large) {
            preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
            preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
        }
    } else {
        VStack(spacing: GitLabDesignTokens.Spacing.large) {
            preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
            preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
        }
    }
}
```

Không đổi `preview(...)`, `GitLabWorkItemList`, spacing hoặc layout breakpoints.

- [ ] **Step 8: Remove obsolete view and preview reference**

Xóa file không còn destination:

```bash
git rm Sources/OpsHub/Features/GitLab/Views/GitLabNotificationsView.swift
```

Trong `GitLabWorkspaceNavigation` preview, thay closure badge bằng:

```swift
badgeCount: { section in section == .pipelines ? 120 : 2 }
```

Xác nhận production source không còn UI copy hoặc section reference:

```bash
rg -n "Recent notifications|GitLabNotificationsView|case \.notifications|for: \.notifications|section: \.notifications" Sources/OpsHub/Features/GitLab
```

Expected: không có kết quả. Các reference tới `GitLabNotification`, notification service, `pendingNotifications` và action queue vẫn được phép tồn tại.

- [ ] **Step 9: Run focused verification**

Run:

```bash
swift test --filter GitLabWorkspaceStateTests
swift test --filter GitLabDashboardViewModelTests
swift test --filter GitLabActionQueueTests
swift build
```

Expected: tất cả pass; navigation có năm destinations; notification vẫn có trong `Pending` và `Action queue`; Overview chỉ còn hai preview.

- [ ] **Step 10: Commit Change Work Items CWI-01 and CWI-02**

```bash
git add Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift Sources/OpsHub/Features/GitLab/Views/GitLabOverviewView.swift Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceNavigation.swift Tests/OpsHubTests/GitLabWorkspaceStateTests.swift Tests/OpsHubTests/GitLabDashboardViewModelTests.swift
git add -u Sources/OpsHub/Features/GitLab/Views/GitLabNotificationsView.swift
git commit -m "fix: remove GitLab notification surfaces"
```

---

### Task 2: Cache the Current GitLab Screen Data Across Sidebar Reopens

**Change Work Item:** CWI-03

**Files:**

- Modify: `Sources/OpsHub/App/ContentView.swift:42-74`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift:4-14,188-192`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift:23-30,266-270,347-354`
- Test: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift:58-74`

**Interfaces:**

- Consumes: arrays, load states, `lastUpdated`, `selectedScope`, `loadDashboard()`, `refresh()`, và `loadingScope` hiện có trong `GitLabDashboardViewModel`.
- Produces: app-owned `GitLabDashboardViewModel`, `GitLabDashboardView.init(viewModel:)`, và một single-entry in-memory cache marker `loadedScope`.

- [ ] **Step 1: Add a failing cache behavior test**

Thêm test sau vào `GitLabDashboardViewModelTests`:

```swift
@MainActor
func testLoadDashboardReusesCurrentScopeUntilManualRefresh() async {
    let service = SlowCountingGitLabService()
    let viewModel = GitLabDashboardViewModel(service: service)

    await viewModel.loadDashboard()
    await viewModel.loadDashboard()

    let callsAfterReopen = await service.callCount()
    XCTAssertEqual(callsAfterReopen, 1)

    await viewModel.refresh()

    let callsAfterManualRefresh = await service.callCount()
    XCTAssertEqual(callsAfterManualRefresh, 2)
}
```

Thêm test xác nhận đổi scope không dùng nhầm cache hiện tại:

```swift
@MainActor
func testLoadDashboardFetchesWhenScopeChanges() async {
    let service = ScopeCountingGitLabService()
    let viewModel = GitLabDashboardViewModel(service: service)
    let project = GitLabProjectSummary(id: 9, nameWithNamespace: "group/project", webURL: nil)

    await viewModel.loadDashboard()
    viewModel.selectedScope = .project(project)
    await viewModel.loadDashboard()

    let loadedScopes = await service.loadedScopes()
    XCTAssertEqual(loadedScopes, ["All projects", "group/project"])
}
```

Thêm test xác nhận initial failure không bị cache:

```swift
@MainActor
func testLoadDashboardRetriesAfterTotalInitialFailure() async {
    let service = CountingFailingGitLabService()
    let viewModel = GitLabDashboardViewModel(service: service)

    await viewModel.loadDashboard()
    await viewModel.loadDashboard()

    let calls = await service.callCount()
    XCTAssertEqual(calls, 2)
}
```

Thêm actor stub đầy đủ ở cuối test file:

```swift
private actor ScopeCountingGitLabService: GitLabServicing {
    private var scopes: [String] = []

    func mergeRequests() async throws -> [GitLabMergeRequest] { [] }

    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        scopes.append(scope.title)
        return []
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] { [] }
    func issues() async throws -> [GitLabIssue] { [] }
    func notifications() async throws -> [GitLabNotification] { [] }
    func pipelines() async throws -> [GitLabPipeline] { [] }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }

    func loadedScopes() -> [String] { scopes }
}

private actor CountingFailingGitLabService: GitLabServicing {
    private var calls = 0

    func projects() async throws -> [GitLabProjectSummary] {
        throw GitLabServiceError.requestFailed(503)
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        calls += 1
        throw GitLabServiceError.requestFailed(503)
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] {
        throw GitLabServiceError.requestFailed(503)
    }

    func issues() async throws -> [GitLabIssue] {
        throw GitLabServiceError.requestFailed(503)
    }

    func notifications() async throws -> [GitLabNotification] {
        throw GitLabServiceError.requestFailed(503)
    }

    func pipelines() async throws -> [GitLabPipeline] {
        throw GitLabServiceError.requestFailed(503)
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        .connected
    }

    func callCount() -> Int { calls }
}
```

- [ ] **Step 2: Run the cache tests and confirm repeated load still fetches**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests
```

Expected: `testLoadDashboardReusesCurrentScopeUntilManualRefresh` fails with call count `2` before manual refresh because `loadDashboard()` currently delegates directly to `refresh()`.

- [ ] **Step 3: Add the minimal current-scope cache marker**

Trong `GitLabDashboardViewModel`, thêm cạnh `loadingScope`:

```swift
private var loadedScope: GitLabProjectScope?
```

Thay `loadDashboard()` bằng:

```swift
func loadDashboard() async {
    let scope = selectedScope
    guard loadedScope != scope else { return }
    await refresh()
}
```

Trong success condition cuối `refresh()`, giữ toàn bộ điều kiện hiện tại và thêm assignment sau `lastUpdated`:

```swift
if projectsResult.value != nil
    || mergeRequestsSucceeded
    || mergeReviewsSucceeded
    || issuesSucceeded
    || notificationsSucceeded
    || pipelinesSucceeded {
    lastUpdated = .now
    loadedScope = scope
}
```

Không thêm guard cache vào `refresh()`: đây là đường đi của nút Refresh và phải luôn gọi service. Nếu total initial load không có result thành công, `loadedScope` vẫn `nil`, nên lần mở sau tiếp tục retry.

- [ ] **Step 4: Hoist ViewModel ownership to ContentView**

Trong `ContentView`, thêm app-screen lifetime state:

```swift
@StateObject private var gitLabViewModel: GitLabDashboardViewModel
```

Thay initializer bằng:

```swift
init(
    navigationState: AppNavigationState,
    settingsStore: any GitLabSettingsStoring = GitLabSettingsStore()
) {
    self.navigationState = navigationState
    self.settingsStore = settingsStore
    _gitLabViewModel = StateObject(
        wrappedValue: GitLabDashboardViewModel(
            service: GitLabService(settingsStore: settingsStore)
        )
    )
}
```

Thay GitLab detail destination bằng:

```swift
case .gitLab:
    GitLabDashboardView(viewModel: gitLabViewModel)
```

`ContentView` vẫn truyền cùng `settingsStore` cho `SettingsView`; không đổi app sidebar hoặc Settings UI.

- [ ] **Step 5: Make GitLabDashboardView observe the injected ViewModel**

Thay property và initializer đầu `GitLabDashboardView` bằng:

```swift
@ObservedObject private var viewModel: GitLabDashboardViewModel

init(viewModel: GitLabDashboardViewModel) {
    _viewModel = ObservedObject(wrappedValue: viewModel)
}
```

Giữ nguyên `.task(id: viewModel.selectedScope)`, header, refresh action và section rendering. Cập nhật preview thành:

```swift
#Preview {
    NavigationStack {
        GitLabDashboardView(viewModel: GitLabDashboardViewModel())
    }
}
```

- [ ] **Step 6: Verify cache, scope and refresh behavior**

Run:

```bash
swift test --filter GitLabDashboardViewModelTests
swift test --filter GitLabServiceTests
swift build
```

Expected:

- Hai `loadDashboard()` liên tiếp với cùng scope chỉ tạo một load cycle.
- `refresh()` sau cache hit tạo load cycle mới.
- Đổi scope tạo request mới.
- Existing concurrent refresh, scope race, partial failure và total failure tests vẫn pass.
- SwiftUI build xác nhận `ContentView` sở hữu ViewModel và `GitLabDashboardView` nhận đúng injected instance.

- [ ] **Step 7: Commit Change Work Item CWI-03**

```bash
git add Sources/OpsHub/App/ContentView.swift Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift Tests/OpsHubTests/GitLabDashboardViewModelTests.swift
git commit -m "perf: reuse GitLab dashboard data on reopen"
```

---

### Task 3: Update Verification Evidence and Run the Release Gate

**Files:**

- Modify: `docs/gitlab-workspace-verification.md:6-53`

**Interfaces:**

- Consumes: hoàn tất Task 1 và Task 2.
- Produces: verification checklist phản ánh năm destinations, hai Overview previews và current-scope in-memory cache.

- [ ] **Step 1: Update verification documentation to the new approved behavior**

Áp dụng các thay đổi nội dung sau trong `docs/gitlab-workspace-verification.md`:

```markdown
- Refresh resilience, duplicate-load prevention, same-scope reopen caching, selection/filter retention and summary routing are covered by `GitLabDashboardViewModelTests`.

- 1440: header is horizontal, summary uses one row, Overview previews use two equal-width columns.

- The app-owned `GitLabDashboardViewModel` keeps the currently loaded scope in memory while navigating between sidebar screens.
- Reopening GitLab with the same scope does not fetch again; changing scope or using Refresh starts a new load cycle.
- Project membership data remains actor-cached within a refresh cycle, shared by project selection and pipeline loading, then invalidated for the next user refresh.

- [x] Five workspace destinations route to real content.
- [x] Pending remains an Overview metric and notification-derived work remains in Action queue.
- [x] Overview uses the common WorkItemList/WorkItemRow contract with two preview sections.
- [x] Merge Requests, Reviews, Issues and Pipelines use the common list contract.
- [x] Reopening GitLab with the same selected scope reuses in-memory data until Refresh or scope change.
```

Không ghi số lượng test cố định; thay dòng hiện tại bằng mô tả suite để tài liệu không stale khi test count thay đổi:

```markdown
- `swift test`: the full suite passes, including multi-project identity, scope-race, current-scope cache, Overview search and cross-source deduplication checks.
```

- [ ] **Step 2: Run the complete automated gate**

Run:

```bash
swift test
swift build
swift build -c release
git diff --check
```

Expected: mọi command exit code `0`; release build không có strict-concurrency error; diff không có whitespace error.

- [ ] **Step 3: Perform the focused manual walkthrough without redesign review**

Run the app:

```bash
swift run OpsHub
```

Verify exactly these behaviors:

1. GitLab navigation shows `Overview`, `Merge Requests`, `Reviews`, `Issues`, `Pipelines` and no Notification Tab.
2. Overview shows `Action queue`, `My merge requests`, `Recent pipelines` and no Recent notifications section.
3. Notification-derived rows can still appear in Action queue and the `Pending` count still reflects notification data.
4. Navigate GitLab -> Brew -> GitLab without changing scope; existing data remains visible and loading indicator/API refresh does not restart.
5. Change project scope; loading starts and the new scope data replaces the current screen data.
6. Click Refresh; loading starts even when the same scope is already cached.
7. Confirm narrow, compact and wide layouts retain the same components, spacing and styling apart from the removed notification surfaces.

- [ ] **Step 4: Commit verification documentation**

```bash
git add docs/gitlab-workspace-verification.md
git commit -m "docs: update GitLab workspace verification"
```

## Self-Review Checklist

- [ ] Requirement 1 maps to Task 1: Notification Tab enum case, route, view, badge/filter state and preview references are removed.
- [ ] Requirement 2 maps to Task 1: Recent notifications is removed in wide and non-wide layouts, leaving the existing two preview components unchanged.
- [ ] Requirement 3 maps to Task 2: same-scope reopen uses the existing ViewModel data; scope change and manual Refresh still fetch.
- [ ] Notification service/model/data remain because `Pending` and `Action queue` still consume them.
- [ ] No API, authentication, settings-storage, design token, list/row component or responsive breakpoint is redesigned.
- [ ] No new dependency, cache service, persistence schema or background refresh mechanism is introduced.
- [ ] Tests cover section order, pending routing, retained notification action data, cache hit, manual refresh and scope change.
- [ ] Type names and method signatures are consistent: `GitLabDashboardView.init(viewModel:)`, `loadedScope`, `loadDashboard()`, `refresh()`.
