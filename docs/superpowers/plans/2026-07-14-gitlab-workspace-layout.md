# GitLab Workspace Layout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chuyển GitLab Dashboard hiện tại thành GitLab Workspace theo hướng action-first, có scope, navigation, summary compact, component dùng chung, dark mode, accessibility và responsive layout cho macOS.

**Architecture:** Giữ luồng `GitLabService -> GitLabDashboardViewModel -> SwiftUI Views`, bổ sung domain state và presentation model để UI không phụ thuộc trực tiếp vào REST model. Tách dần `GitLabComponents.swift` thành các component nhỏ theo trách nhiệm; mỗi Work Item phải tạo ra một thay đổi có thể review, build và kiểm thử độc lập.

**Tech Stack:** Swift 6, SwiftUI, Foundation, XCTest, Swift Package Manager, macOS 14+.

## Global Constraints

- Không thay đổi GitLab authentication hoặc cách lưu personal access token.
- Không đổi business rule của các Issues tab `Assign me`, `Test`, `Passed`, `Build`, `Bug Pro`.
- Scope mặc định là `All projects`; filter và selection chỉ cần được giữ trong phiên hiện tại.
- Không thêm thư viện UI hoặc state-management mới.
- Mọi state nghiệp vụ phải kiểm thử được mà không phụ thuộc SwiftUI rendering.
- Mọi component mới phải hỗ trợ light mode, dark mode, keyboard focus và VoiceOver ngay từ Work Item tạo component.
- Không dùng màu làm tín hiệu trạng thái duy nhất.
- Không thêm tối ưu hóa phức tạp trước khi có số liệu profiling ở Work Item 15.
- Sau từng Work Item: chạy test mục tiêu và `swift build`; chạy `swift test` đầy đủ tại các integration checkpoint được nêu trong plan.
- Mỗi Work Item được commit riêng sau khi verification pass.

## Target File Structure

```text
Sources/OpsHub/Features/GitLab/
├── Components/
│   ├── GitLabAdaptiveLayout.swift
│   ├── GitLabAvatarGroup.swift
│   ├── GitLabComponents.swift
│   ├── GitLabDesignTokens.swift
│   ├── GitLabStatusBadge.swift
│   ├── GitLabSummaryStrip.swift
│   ├── GitLabSurface.swift
│   ├── GitLabWorkItemList.swift
│   ├── GitLabWorkItemRow.swift
│   ├── GitLabWorkspaceHeader.swift
│   └── GitLabWorkspaceNavigation.swift
├── Models/
│   ├── GitLabModels.swift
│   ├── GitLabRESTModels.swift
│   └── GitLabWorkItemPresentation.swift
├── Services/
│   └── GitLabServices.swift
├── ViewModels/
│   └── GitLabDashboardViewModel.swift
└── Views/
    ├── GitLabDashboardView.swift
    ├── GitLabIssuesView.swift
    ├── GitLabMergeRequestsView.swift
    ├── GitLabNotificationsView.swift
    ├── GitLabOverviewView.swift
    ├── GitLabPipelinesView.swift
    └── GitLabReviewsView.swift
```

---

## Work Item 1 — Domain Contract và Workspace State

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift`
- Create test: `Tests/OpsHubTests/GitLabWorkspaceStateTests.swift`

### Components to create

- `GitLabWorkspaceSection`: sáu section với identity ổn định và thứ tự hiển thị.
- `GitLabSummaryMetricKind`: định danh bốn metric, không dùng title làm identity.
- `GitLabCount`: phân biệt `total`, `actionable`, `unread`, `visible`.
- `GitLabActionPriority`: severity dùng cho action queue.
- `GitLabWorkspaceSelection`: selected section và selected work item.

### Components to modify

- `GitLabDashboardViewModel`: sở hữu section/selection state.
- `GitLabStatistic`: giữ tạm để tương thích trong giai đoạn chuyển đổi, đánh dấu sẽ bị thay bởi summary metric ở Work Item 10.
- `GitLabIssueTab`: giữ nguyên cases và `includes(_:)`.

### Dependencies and outputs

- Consumes: Không có Work Item trước; dùng domain models hiện tại.
- Produces: typed workspace section, metric/count semantics, shared selection state và action-priority contract cho WI 3, 7, 10, 11.

### Implementation order

- [ ] Viết `GitLabWorkspaceStateTests` cho section order, stable identity, count semantics và action priority order.
- [ ] Chạy test mới, xác nhận fail vì contract chưa tồn tại.
- [ ] Thêm domain types vào `GitLabModels.swift` mà chưa đổi layout.
- [ ] Chuyển selected section/item state từ View cục bộ sang `GitLabDashboardViewModel`.
- [ ] Cập nhật test ViewModel để dùng tên `Reviews` thay cho `Merge Review` tại contract mới; không xóa compatibility code của UI cũ.
- [ ] Chạy `GitLabWorkspaceStateTests`, `GitLabDashboardViewModelTests`, `GitLabIssueTabTests` và `swift build`.
- [ ] Commit riêng Work Item 1.

### Risks

- Dùng display string làm identity sẽ gây mất selection khi copy thay đổi.
- Đưa toàn bộ UI state vào ViewModel có thể làm ViewModel giữ state thuần trình bày không cần thiết; chỉ đưa state cần chia sẻ giữa sections.
- Đổi tên Reviews quá sớm có thể làm test snapshot/count hiện tại fail không chủ ý.

### Verification steps

- Run: `swift test --filter GitLabWorkspaceStateTests`
- Expected: section order là Overview, Merge Requests, Reviews, Issues, Pipelines, Notifications; identity không phụ thuộc localized title.
- Run: `swift test --filter GitLabIssueTabTests`
- Expected: toàn bộ behavior hiện tại của năm Issue tabs pass.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: load data và partial-error tests hiện tại vẫn pass.
- Run: `swift build`
- Expected: build thành công, chưa có layout regression do Work Item này không đổi layout.

---

## Work Item 2 — Project Scope Data Source

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabRESTModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabProjectScope`: `allProjects` hoặc một project theo GitLab project ID.
- `GitLabProjectSummary`: domain representation cho project selector.
- Service operation tải membership projects một lần và tái sử dụng cho pipeline/scope.

### Components to modify

- `GitLabServicing`: bổ sung project catalog và scope-aware operations.
- `GitLabService`: tái sử dụng request projects hiện có, không tạo request catalog trùng.
- `GitLabDashboardViewModel`: tải project catalog và giữ `selectedScope`.
- Test stubs conforming `GitLabServicing`: bổ sung operation mới.

### Dependencies and outputs

- Consumes: workspace state và stable identities từ WI 1.
- Produces: project catalog, selected scope và scope-aware service contract cho WI 3, 4, 6, 14.

### Implementation order

- [ ] Viết service tests cho project pagination, mapping namespace và scope-specific request.
- [ ] Chạy `GitLabServiceTests`, xác nhận test mới fail vì protocol chưa có project catalog.
- [ ] Thêm domain scope/project types.
- [ ] Mở rộng `GitLabServicing` và cập nhật toàn bộ stub/fake để project compile trở lại.
- [ ] Tách project fetch thành operation tái sử dụng bởi pipeline loading.
- [ ] Truyền selected scope vào các operation MR, review, issues, pipelines và notifications theo khả năng của API.
- [ ] Thêm `All projects` làm scope mặc định trong ViewModel.
- [ ] Chạy service tests, ViewModel tests và build.
- [ ] Commit riêng Work Item 2.

### Risks

- Project request bị gọi hai lần: một lần cho selector, một lần cho pipelines.
- Một số GitLab endpoint không hỗ trợ cùng query parameter scope; cần lọc client-side thay vì gửi parameter không hợp lệ.
- Project ID có thể tồn tại nhưng `name_with_namespace` thiếu; phải có fallback ổn định.
- Thay đổi protocol làm toàn bộ test stubs không compile nếu cập nhật thiếu.

### Verification steps

- Run: `swift test --filter GitLabServiceTests`
- Expected: project pagination, mapping và existing request tests pass.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: default scope là All projects và injected service vẫn tải đủ sections.
- Inspect captured requests in service tests.
- Expected: project catalog không bị fetch trùng trong cùng một refresh cycle.
- Run: `swift build`
- Expected: mọi `GitLabServicing` conformance compile.

---

## Work Item 3 — Search, Filter và Sort Engine

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Create test: `Tests/OpsHubTests/GitLabWorkspaceFilterTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift`

### Components to create

- `GitLabWorkspaceFilter`: scope, search text, status, labels và participant filters.
- `GitLabWorkspaceSort`: actionable priority hoặc updated-descending.
- Pure filtering/sorting functions có thể test độc lập.

### Components to modify

- `GitLabDashboardViewModel`: giữ filter state theo section, expose visible collections và clear-filter operation.
- `GitLabIssueTab`: tiếp tục là workflow filter riêng, áp dụng trước additional filters.

### Dependencies and outputs

- Consumes: workspace state từ WI 1 và project scope từ WI 2.
- Produces: pure filter/sort operations và per-section visible collections cho WI 6, 7, 10–14.

### Implementation order

- [ ] Viết tests cho search normalization, scope filter, clear filters, stable sorting và Issue workflow composition.
- [ ] Chạy test mới, xác nhận fail.
- [ ] Thêm filter/sort domain types.
- [ ] Implement pure search/filter/sort transformations.
- [ ] Tích hợp transformations vào ViewModel mà chưa thay UI.
- [ ] Bảo đảm clear additional filters không reset selected project hoặc Issue workflow tab.
- [ ] Chạy filter tests, Issue tab tests, ViewModel tests và build.
- [ ] Commit riêng Work Item 3.

### Risks

- Áp dụng workflow tab sau generic label filter có thể làm sai count.
- Sort chỉ dùng relative-time string sẽ không ổn định; phải dùng timestamp thật khi available.
- Giữ một filter object chung cho mọi section có thể khiến filter không áp dụng được làm ẩn dữ liệu ngoài ý muốn.

### Verification steps

- Run: `swift test --filter GitLabWorkspaceFilterTests`
- Expected: search không phân biệt hoa thường, trim whitespace, stable tie-break và clear-filter behavior pass.
- Run: `swift test --filter GitLabIssueTabTests`
- Expected: project boundary và label rules không thay đổi.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: visible count phản ánh scope và filters.
- Run: `swift build`
- Expected: build thành công.

---

## Work Item 4 — Resilient Loading và Stale Data

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabSectionLoadState`: idle, initial-loading, loaded, refreshing, stale, failed.
- `GitLabSectionSnapshot<Value>`: data cuối cùng, load state, error và updated-at.
- ViewModel operations cho initial load, refresh và retry section.

### Components to modify

- `GitLabDashboardViewModel`: thay `isLoading` toàn cục bằng page/section state có nghĩa rõ ràng.
- `loadSection`: trả snapshot/result mà không tự xóa dữ liệu cũ.

### Dependencies and outputs

- Consumes: workspace state từ WI 1 và scope-aware loading từ WI 2.
- Produces: page/section load snapshots, stale/error/retry contract cho WI 6, 9, 11–15.

### Implementation order

- [ ] Thêm tests: initial load, success-refresh, partial failure, total failure, success-then-failure và duplicate refresh.
- [ ] Chạy tests, xác nhận success-then-failure fail với behavior hiện tại.
- [ ] Thêm section load-state và snapshot model.
- [ ] Chuyển từng collection sang snapshot hoặc state tương đương mà vẫn expose data cho UI cũ.
- [ ] Giữ successful data gần nhất khi refresh thất bại.
- [ ] Ngăn refresh mới khi refresh hiện tại chưa kết thúc.
- [ ] Định nghĩa `lastUpdated`: page timestamp chỉ đổi khi refresh có ít nhất một section thành công; section timestamp đổi theo section thành công.
- [ ] Chạy ViewModel tests và build.
- [ ] Commit riêng Work Item 4.

### Risks

- Generic snapshot với `@Published` có thể làm SwiftUI observation phức tạp; ưu tiên state rõ, không tạo abstraction khó debug.
- Page-level warning có thể che mất section-level error.
- Nếu refresh bị hủy, state có thể mắc ở refreshing nếu defer/cancellation không xử lý đúng.

### Verification steps

- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: successful data được giữ sau failed refresh; section thành công vẫn cập nhật trong partial failure.
- Add a test with two concurrent refresh calls.
- Expected: service operation count chỉ tăng cho một refresh cycle.
- Run: `swift build`
- Expected: UI cũ vẫn compile qua compatibility accessors.

---

## Work Item 5 — Semantic Design Foundation

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabComponents.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabDesignTokens.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabSurface.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabStatusBadge.swift`

### Components to create

- `GitLabDesignTokens`: spacing, radius, border và semantic color accessors.
- `GitLabSurface`: reusable bordered surface không phụ thuộc shadow.
- `GitLabStatusBadge`: status label có text, optional icon và severity.
- Reusable focus/hover/selected visual modifiers.

### Components to modify

- `StatisticCard`, `GitLabListCard`, `RowHoverBackground`, `GitLabBadge`, `GitLabLabelBadge`: chuyển sang foundation mới nhưng chưa đổi layout tổng thể.

### Dependencies and outputs

- Consumes: severity/status semantics từ WI 1.
- Produces: semantic tokens, surfaces, badges và interaction-state modifiers cho WI 6, 7, 9, 10 và mọi section view.

### Implementation order

- [ ] Xác định semantic tokens từ approved specification.
- [ ] Tạo token file và previews light/dark.
- [ ] Tạo `GitLabSurface` và chuyển một card hiện tại sang dùng surface để xác nhận contract.
- [ ] Tạo `GitLabStatusBadge`, map status hiện tại sang severity và icon.
- [ ] Chuyển hover/selected/focus thành các state phân biệt.
- [ ] Chuyển GitLab label fallback sang semantic contrast-safe colors.
- [ ] Kiểm tra Reduce Motion cho animation hiện tại.
- [ ] Chạy build và visual preview review.
- [ ] Commit riêng Work Item 5.

### Risks

- `Material` có kết quả khác nhau theo wallpaper và accessibility transparency settings.
- GitLab cung cấp label color tùy ý; không thể tin `text_color` luôn đạt contrast.
- Tạo quá nhiều tokens không dùng sẽ tăng maintenance; chỉ định nghĩa token có consumer trong plan.

### Verification steps

- Open SwiftUI previews for light and dark appearances.
- Expected: surface boundaries rõ mà không cần shadow nặng; focus khác hover và selected.
- Enable Increase Contrast and Reduce Transparency in preview/runtime check.
- Expected: text và border vẫn đọc được.
- Enable Reduce Motion.
- Expected: hover/selection không dùng scale animation gây chuyển động không cần thiết.
- Run: `swift build`
- Expected: build thành công.

---

## Work Item 6 — Adaptive Shell và Header

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceHeader.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabAdaptiveLayout.swift`

### Components to create

- `GitLabWorkspaceHeader`: title, scope selector, search, updated time, refresh và connection/stale indicator.
- `GitLabAdaptiveLayout`: wide, compact, narrow layout decision từ available width.
- Header previews tại 720, 960 và 1440 px.

### Components to modify

- `GitLabDashboardView`: dùng workspace header, chỉ giữ một page `ScrollView`.
- Không thay đổi `ContentView` hoặc sidebar navigation; adaptive layout đọc available width bên trong GitLab detail view.

### Dependencies and outputs

- Consumes: project scope từ WI 2, search/filter state từ WI 3, load state từ WI 4 và design foundation từ WI 5.
- Produces: adaptive page shell, header controls và single-scroll-owner contract cho WI 7, 10–14.

### Implementation order

- [ ] Tạo adaptive layout component và previews cho ba width contract.
- [ ] Tạo header từ ViewModel state của WI 2–4.
- [ ] Kết nối scope selector và search controls.
- [ ] Chuyển refresh về một secondary action duy nhất; xóa duplicate toolbar/header action.
- [ ] Đổi page title thành `GitLab` và subtitle thành scope/current-state context.
- [ ] Thiết lập một scroll owner chính và tránh nested page scrolling.
- [ ] Kiểm tra header trong initial-loading, refreshing, stale và unauthorized state.
- [ ] Chạy build, targeted tests và resize QA.
- [ ] Commit riêng Work Item 6.

### Risks

- Dựa vào screen size thay vì available container width sẽ sai trong NavigationSplitView.
- Search và scope selector có thể ép header vượt 720 px nếu không chuyển hàng.
- Giữ cả toolbar refresh và header refresh sẽ làm duplicated action/keyboard shortcut.

### Verification steps

- Render/preview at widths 720, 960, 1440.
- Expected: không overlap, không horizontal overflow, controls vẫn có accessible labels.
- Resize app window continuously across 840 and 1180 boundaries.
- Expected: layout chuyển ổn định, không oscillate hoặc mất focus.
- Trigger background refresh.
- Expected: dữ liệu/header không biến thành initial-loading screen.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Run: `swift build`
- Expected: tests và build pass.

---

## Work Item 7 — Navigation và Section Routing

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceNavigation.swift`
- Modify: `Tests/OpsHubTests/GitLabWorkspaceStateTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabWorkspaceNavigation`: six tabs, badges, active state và overflow behavior.
- Section content router trong `GitLabDashboardView`.

### Components to modify

- `GitLabDashboardViewModel`: section selection, badge values và per-section retained state.
- `GitLabDashboardView`: render section placeholder/content mà không trigger refresh khi tab đổi.

### Dependencies and outputs

- Consumes: typed sections từ WI 1, filters từ WI 3 và adaptive shell từ WI 6.
- Produces: navigation component, section router và destination contract cho WI 10–14.

### Implementation order

- [ ] Viết tests cho section selection, badge 0/99+, retained state và no-refresh-on-navigation.
- [ ] Tạo navigation component với active/focus/accessibility states.
- [ ] Kết nối navigation với ViewModel selection.
- [ ] Thêm content router và giữ Overview làm default.
- [ ] Implement narrow overflow/scroll behavior, bảo đảm active tab luôn nhìn thấy.
- [ ] Xác nhận đổi tab không gọi service.
- [ ] Chạy tests, build và keyboard review.
- [ ] Commit riêng Work Item 7.

### Risks

- Dùng segmented picker cho sáu tab có thể co chữ quá mức ở narrow width.
- Badge cập nhật có thể làm tab width thay đổi và gây layout shift.
- Section View được tạo lại có thể mất local scroll/filter state; state cần nằm ở ViewModel hoặc stable child identity.

### Verification steps

- Run: `swift test --filter GitLabWorkspaceStateTests`
- Expected: default section là Overview, selected section giữ ổn định.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: changing section không gọi service; badge zero bị ẩn ở presentation state.
- Keyboard navigate across all six tabs.
- Expected: focus visible, active tab được chọn bằng Space/Enter.
- Resize to 720 px.
- Expected: active tab vẫn nhìn thấy và tên tab không biến thành icon-only.
- Run: `swift build`

---

## Work Item 8 — Unified Work Item Presentation Model

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabRESTModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Create test: `Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift`

### Components to create

- `GitLabWorkItemPresentation`: common identifier, title, project, status, severity, participants, labels, updated date, display time và optional URL.
- Adapters from `GitLabMergeRequest`, `GitLabIssue`, `GitLabPipeline`, `GitLabNotification`.
- Accessibility summary builder.

### Components to modify

- Domain models: giữ `Date?`/timestamp thật bên cạnh relative display text.
- `GitLabService` mappers: map pipeline/notification URL nếu REST payload cung cấp.
- REST models: decode URL/time fields đang chưa được domain sử dụng.

### Dependencies and outputs

- Consumes: status/severity semantics từ WI 1 và project identity từ WI 2.
- Produces: UI-independent presentation model và adapters cho WI 9, 11–14.

### Implementation order

- [ ] Viết presentation tests cho năm item variants, missing URL, missing avatar, project fallback và full timestamp.
- [ ] Chạy tests mới, xác nhận fail.
- [ ] Thêm presentation model không import SwiftUI.
- [ ] Bổ sung domain timestamp/URL fields với initializer defaults để giảm migration breakage.
- [ ] Cập nhật REST decoding/mapping và service fixtures.
- [ ] Implement adapters và accessibility summary.
- [ ] Chạy presentation tests, service tests và build.
- [ ] Commit riêng Work Item 8.

### Risks

- Thêm non-default initializer parameters sẽ làm nhiều fixtures compile fail; dùng defaults có chủ đích cho compatibility rồi cập nhật fixtures dần.
- GitLab notification URL không phải payload nào cũng có; không tự dựng URL sai target.
- Hai MR lists dùng cùng domain type nhưng context/status presentation có thể khác.

### Verification steps

- Run: `swift test --filter GitLabWorkItemPresentationTests`
- Expected: adapters tạo đúng identifier, status, URL optional và accessibility summary.
- Run: `swift test --filter GitLabServiceTests`
- Expected: REST decoding/mapping tests pass, kể cả payload thiếu URL/date.
- Run: `swift build`
- Expected: toàn bộ fixtures và previews compile.

---

## Work Item 9 — Reusable Work Item List và Row

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemList.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`
- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabAvatarGroup.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabComponents.swift`

### Components to create

- `GitLabWorkItemList`: section header, visible count, load/empty/error/content states và lazy rows.
- `GitLabWorkItemRow`: shared row layout từ presentation model.
- `GitLabAvatarGroup`: tối đa ba avatars, `+N`, initials fallback.
- Quick-action region tách khỏi primary row action.

### Components to modify

- `GitLabSelectableRow`, `MergeRequestRow`, `IssueRow`: chuyển thành compatibility wrappers rồi xóa khi consumers đã migrate ở WI 12–14.
- `GitLabFlowLayout` và `GitLabLabelBadge`: chuyển sang dùng design foundation, giữ label wrapping.

### Dependencies and outputs

- Consumes: design primitives từ WI 5 và presentation contract từ WI 8.
- Produces: reusable list/row/avatar components và list-state slots cho WI 11–14.

### Implementation order

- [ ] Tạo previews cho MR, issue nhiều labels, pipeline, notification, long title, missing URL và missing avatar.
- [ ] Tạo AvatarGroup với accessibility names và initials fallback.
- [ ] Tạo WorkItemRow với wide/narrow arrangements.
- [ ] Tách primary open action khỏi quick-action button hit region.
- [ ] Tạo WorkItemList với initial/loading/refreshing/empty/filtered-empty/error/stale states.
- [ ] Dùng lazy row construction; chưa thêm custom virtualization.
- [ ] Thêm compatibility wrappers để UI cũ tiếp tục hoạt động.
- [ ] Chạy build và preview matrix review.
- [ ] Commit riêng Work Item 9.

### Risks

- Một Button chứa Button khác là interaction/accessibility không hợp lệ; row và quick action phải là sibling hit regions.
- Labels không giới hạn có thể làm row quá cao; giữ đầy đủ labels nhưng cho wrapping có kiểm soát.
- SwiftUI `List` có styling/selection behavior khác `LazyVStack`; component phải chọn một scroll owner thống nhất với WI 6.

### Verification steps

- Preview row ở widths tương ứng narrow/wide.
- Expected: identifier không truncate; title tối đa một dòng wide, hai dòng narrow; labels không che badge/time.
- Test click primary row and quick action manually.
- Expected: quick action không mở row URL hai lần.
- Enable VoiceOver.
- Expected: row đọc type, identifier, title, project, status, participants, updated time và available action.
- Run: `swift build`
- Expected: build thành công.

---

## Work Item 10 — Compact Summary Strip

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Components/GitLabSummaryStrip.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabComponents.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Modify: `Tests/OpsHubTests/GitLabWorkspaceStateTests.swift`

### Components to create

- `GitLabSummaryStrip`.
- `GitLabSummaryMetricView`.
- ViewModel summary metrics derived from current scope/data.

### Components to modify

- `GitLabDashboardView`: thay statistic grid bằng summary strip.
- `StatisticCard`: xóa sau khi không còn consumer.
- `GitLabDashboardViewModel.makeStatistics`: thay bằng summary derivation dùng typed metric kinds.

### Dependencies and outputs

- Consumes: count/filter state từ WI 1, 3, load/scope state từ WI 2, 4, design foundation từ WI 5 và routing từ WI 7.
- Produces: four-metric summary strip và metric-to-destination actions cho WI 11, 14.

### Implementation order

- [ ] Viết tests cho bốn metric counts và metric-to-section/filter routing.
- [ ] Tạo SummaryMetricView với keyboard/VoiceOver support.
- [ ] Tạo adaptive strip: one row, 2x2, 1x4.
- [ ] Kết nối metrics với selected scope và current data snapshots.
- [ ] Kết nối metric action với navigation/filter state.
- [ ] Thay statistic grid trong dashboard và xóa StatisticCard code không còn dùng.
- [ ] Chạy tests, build và visual QA ở ba widths.
- [ ] Commit riêng Work Item 10.

### Risks

- Count unread/actionable có thể chưa có field trực tiếp từ GitLab; chỉ dùng semantics đã chứng minh từ payload hiện tại.
- Metric click có thể reset filter người dùng đang dùng; metric action phải đặt filter có chủ đích cho destination, không reset các section khác.
- Grid adaptive tự động có thể tạo ba cột ngoài specification; dùng explicit mode từ adaptive layout.

### Verification steps

- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: counts đúng theo scope và failed/unread/actionable semantics.
- Run: `swift test --filter GitLabWorkspaceStateTests`
- Expected: từng metric mở đúng section/filter.
- Preview at 720, 960, 1440.
- Expected: summary cao không quá khoảng 96 px ở wide mode và không tạo cột ngoài specification.
- Run: `swift build`

---

## Work Item 11 — Overview Action Queue

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabOverviewView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Create test: `Tests/OpsHubTests/GitLabActionQueueTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabOverviewView`.
- Pure action queue builder/deduplicator.
- Primary `Cần xử lý` list.
- Secondary previews: My Merge Requests, Recent Pipelines, Recent Notifications.

### Components to modify

- `GitLabDashboardView`: route Overview sang view mới.
- `GitLabDashboardViewModel`: expose action queue và limited preview collections.

### Dependencies and outputs

- Consumes: filtering/sorting từ WI 3, routing từ WI 7, reusable rows từ WI 9 và summary destinations từ WI 10.
- Produces: action-first Overview, deduplicated queue và secondary previews cho product integration review.

### Implementation order

- [ ] Viết tests cho inclusion, deduplication, severity ordering, time tie-break và preview limits.
- [ ] Implement pure action queue builder từ presentation models.
- [ ] Tạo Overview wide two-column và compact/narrow one-column layouts.
- [ ] Render action queue bằng WorkItemList.
- [ ] Render secondary previews với giới hạn cố định và content-height tự nhiên.
- [ ] Kết nối View All với section/scope/filter tương ứng.
- [ ] Thêm empty action queue state không mang nghĩa lỗi.
- [ ] Chạy tests, build và product visual review.
- [ ] Commit riêng Work Item 11.

### Risks

- Một MR có thể xuất hiện ở review request và notification; dedupe key phải chứa resource type/project/id, không chỉ title.
- Relative time không đủ để sort; dùng timestamp thật.
- Secondary previews có thể lặp lại item ở primary queue; đây là chấp nhận được chỉ khi section label làm rõ mục đích, nhưng không được duplicate trong cùng một list.

### Verification steps

- Run: `swift test --filter GitLabActionQueueTests`
- Expected: failed/blocked trước normal, stable tie-break, không duplicate trong action queue.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: preview limits và View All destination đúng.
- Preview empty, one-item và full datasets at three widths.
- Expected: section không bị ép cùng chiều cao và action queue đứng trước secondary content.
- Run: `swift build`

---

## Work Item 12 — Merge Requests và Reviews Sections

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabMergeRequestsView.swift`
- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabReviewsView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabComponents.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabMergeRequestsView`.
- `GitLabReviewsView`.
- Shared section filter bar configuration for MR/review status and project.

### Components to modify

- Dashboard section router.
- ViewModel visible MR/review collections and selection state.
- Remove `MergeRequestsCard`, `MergeReviewsCard`, `MergeRequestRow` after migration.

### Dependencies and outputs

- Consumes: filter state từ WI 3, routing từ WI 7, presentation model từ WI 8 và reusable rows từ WI 9.
- Produces: completed Merge Requests và Reviews sections, đồng thời loại bỏ MR compatibility components.

### Implementation order

- [ ] Bổ sung ViewModel tests cho separate MR/review scope, filtered counts và retained selection.
- [ ] Tạo MR view bằng WorkItemList và shared filter controls.
- [ ] Tạo Reviews view bằng cùng components, khác source/filter preset.
- [ ] Kết nối open action, clear filters và selection restoration.
- [ ] Kết nối section router.
- [ ] Xóa card/row cũ sau khi không còn references.
- [ ] Chạy targeted tests, full test và build.
- [ ] Commit riêng Work Item 12.

### Risks

- Cùng một `GitLabMergeRequest` có thể nằm trong cả assigned và reviews-for-me; hai section phải giữ selection/filter độc lập.
- Xóa compatibility wrappers trước khi previews/Overview migrate hết sẽ làm build fail.
- Status Approved hiện có thể là presentation inference, không phải authoritative approval state; không thay đổi mapping trong UI task này.

### Verification steps

- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: MR/review filters và selections độc lập; counts đúng.
- Navigate MR -> Reviews -> MR.
- Expected: filter, selection và scroll intent được giữ trong phiên.
- Test empty, filtered-empty, refreshing, stale và unauthorized states.
- Expected: mỗi state có message/action đúng.
- Run: `swift test`
- Run: `swift build`
- Expected: full suite và build pass.

---

## Work Item 13 — Issues Section và Workflow Tabs

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabIssuesView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabComponents.swift`
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabIssuesView`.
- Workflow-tab control giữ nguyên năm tab và không tự co thành icon.
- Issue-specific supplementary filter controls.

### Components to modify

- `GitLabDashboardView`: route Issues sang view mới.
- `GitLabDashboardViewModel`: selected Issue tab, additional filters, visible count, selection.
- Remove `IssuesCard` và `IssueRow` after migration.

### Dependencies and outputs

- Consumes: composed filters từ WI 3, routing từ WI 7, presentation model từ WI 8 và reusable rows từ WI 9.
- Produces: completed Issues section giữ nguyên workflow contract và loại bỏ Issue compatibility components.

### Implementation order

- [ ] Mở rộng Issue tab tests cho composition với project scope và additional filters.
- [ ] Đưa selected Issue tab từ local `@State` sang ViewModel retained state.
- [ ] Tạo workflow-tab control với narrow horizontal/overflow behavior giữ nguyên text labels.
- [ ] Tạo Issues view bằng WorkItemList, label flow và full issue content policy.
- [ ] Kết nối additional filters và clear behavior không reset workflow tab/project scope.
- [ ] Kết nối router và xóa IssuesCard/IssueRow cũ.
- [ ] Chạy Issue tests, ViewModel tests, full test và build.
- [ ] Commit riêng Work Item 13.

### Risks

- Generic filter có thể vô tình mở rộng workflow tab ra ngoài workflow project.
- `Assign me` copy hiện tại không chuẩn ngữ pháp nhưng là approved tab; không tự đổi copy trong implementation.
- Nhiều labels có thể làm row cao; không được ẩn label nghiệp vụ chỉ để cố định chiều cao.

### Verification steps

- Run: `swift test --filter GitLabIssueTabTests`
- Expected: toàn bộ rule Testing/ToTest, Passed/ToProduction, Build/Merged, Bug Production và project boundary pass.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: Issue tab/filter state được giữ khi đổi section.
- Preview long titles and many labels in light/dark at 720 px.
- Expected: labels wrap, không che priority/time/action.
- Run: `swift test`
- Run: `swift build`

---

## Work Item 14 — Pipelines và Notifications Sections

### Files to edit

- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabPipelinesView.swift`
- Create: `Sources/OpsHub/Features/GitLab/Views/GitLabNotificationsView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`

### Components to create

- `GitLabPipelinesView` với failed preset.
- `GitLabNotificationsView` với unread/actionable preset theo semantics có trong data.
- Project-level pipeline partial-error presentation.

### Components to modify

- Dashboard router.
- ViewModel visible pipeline/notification collections, filters và counts.
- `GitLabService.pipelines`: giữ project successes khi một project fail.
- Notification/pipeline presentation mapping từ WI 8: cung cấp đủ verified payload fields cho hai section mới.

### Dependencies and outputs

- Consumes: scope/loading/filter contracts từ WI 2–4, routing từ WI 7, presentation model từ WI 8 và reusable rows từ WI 9.
- Produces: completed Pipelines/Notifications sections, failed/unread destinations và project-level partial-warning behavior.

### Implementation order

- [ ] Bổ sung service tests cho one-project failure và preserved successes.
- [ ] Bổ sung ViewModel tests cho failed/unread/actionable presets và summary routing.
- [ ] Cập nhật pipeline loading để giữ kết quả project thành công cùng warning cho project lỗi.
- [ ] Tạo Pipelines view bằng WorkItemList.
- [ ] Tạo Notifications view bằng WorkItemList.
- [ ] Kết nối filters, open actions, retry và router.
- [ ] Xác nhận Overview/summary destination sử dụng đúng presets.
- [ ] Chạy targeted tests, full test và build.
- [ ] Commit riêng Work Item 14.

### Risks

- GitLab notifications payload hiện tại có thể không cung cấp authoritative unread state; không gọi mọi notification là unread nếu chưa có evidence.
- Pipeline fetch theo nhiều project có thể tạo nhiều request và chậm; không tăng project limit trong UI task này.
- Swallow mọi project error sẽ làm người dùng tin dữ liệu đầy đủ; phải hiển thị partial warning.

### Verification steps

- Run: `swift test --filter GitLabServiceTests`
- Expected: một project pipeline fail không xóa results của project khác; warning/error context được giữ.
- Run: `swift test --filter GitLabDashboardViewModelTests`
- Expected: failed pipeline metric mở Pipelines với failed filter; notification metric dùng count semantics đã xác nhận.
- Test items with and without URL.
- Expected: chỉ item có URL hiển thị open action.
- Run: `swift test`
- Run: `swift build`
- Expected: full suite và build pass.

---

## Work Item 15 — Accessibility, Performance và Release Hardening

### Files to edit

- Modify: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabAdaptiveLayout.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabStatusBadge.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabSummaryStrip.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemList.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceHeader.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceNavigation.swift`
- Modify: `Sources/OpsHub/Features/GitLab/ViewModels/GitLabDashboardViewModel.swift`
- Modify: `Tests/OpsHubTests/GitLabDashboardViewModelTests.swift`
- Modify: `Tests/OpsHubTests/GitLabWorkspaceStateTests.swift`
- Modify: `Tests/OpsHubTests/GitLabActionQueueTests.swift`
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift`
- Create: `docs/gitlab-workspace-verification.md`

### Components to create

- Không tạo thêm production abstraction trừ khi audit chứng minh component hiện tại không đáp ứng contract.
- `gitlab-workspace-verification.md`: checklist và evidence cho accessibility, responsive, dark mode, performance và regression.

### Components to modify

- Tất cả component được audit theo keyboard, VoiceOver, contrast, text scaling và Reduce Motion.
- WorkItemList/ViewModel chỉ được tối ưu sau profiling evidence.

### Dependencies and outputs

- Consumes: toàn bộ production deliverables và tests từ WI 1–14.
- Produces: verified release candidate, profiling evidence, accessibility/visual QA record và `docs/gitlab-workspace-verification.md`.

### Implementation order

- [ ] Chạy full build/test baseline trước audit và ghi kết quả.
- [ ] Audit keyboard traversal, focus order, Enter/Space/Escape behavior và keyboard traps.
- [ ] Audit VoiceOver output cho header, navigation, summary, filters và năm item variants.
- [ ] Audit light/dark, Increase Contrast, Reduce Transparency, Reduce Motion và text scaling.
- [ ] QA resize liên tục và fixed widths 720, 960, 1440.
- [ ] Profile representative large datasets; ghi render/scroll behavior và request count.
- [ ] Chỉ sửa performance issue được profiling chứng minh; ưu tiên lazy rendering, cache reuse và tránh duplicate loads trước custom virtualization.
- [ ] Verify selection, filter và scroll restoration sau navigation/open/refresh.
- [ ] Chạy full regression sau mọi correction.
- [ ] Hoàn thiện verification document và PR/MR verification notes.
- [ ] Commit riêng Work Item 15.

### Risks

- Dồn accessibility đến cuối có thể tạo rework; Work Items 5–14 đã có accessibility acceptance riêng, WI 15 chỉ là integration audit.
- Performance test với mock data không đại diện network latency; tách rendering evidence khỏi network evidence.
- Custom virtualization trên macOS SwiftUI có rủi ro selection/focus regression; chỉ thực hiện nếu lazy rendering không đạt.
- Sửa visual findings cuối kỳ có thể làm đổi layout đã product-approved; mọi thay đổi cấu trúc phải quay lại product review.

### Verification steps

- Run: `swift build`
- Expected: build thành công.
- Run: `swift test`
- Expected: toàn bộ test suite pass.
- Keyboard-only walkthrough: header -> navigation -> summary -> filters -> rows -> quick actions.
- Expected: mọi control reachable, focus visible, không keyboard trap.
- VoiceOver walkthrough for all sections.
- Expected: labels, values, states và actions đọc đúng; decorative icons bị ẩn.
- Appearance matrix: light/dark, Increase Contrast, Reduce Transparency, Reduce Motion.
- Expected: không mất text/status/focus signal.
- Width matrix: 720, 960, 1440 và continuous resize.
- Expected: không overlap, không mất action, không horizontal overflow ngoài navigation được thiết kế.
- Refresh/route walkthrough.
- Expected: background refresh giữ data/selection; section navigation giữ filter; stale data được đánh dấu.
- Review `docs/gitlab-workspace-verification.md`.
- Expected: có evidence cho từng acceptance criterion của approved design specification.

---

## Cross-Work-Item Dependency Order

1. WI 1 — Domain Contract và Workspace State.
2. WI 2 — Project Scope Data Source.
3. WI 3 — Search, Filter và Sort Engine.
4. WI 4 — Resilient Loading và Stale Data.
5. WI 5 — Semantic Design Foundation.
6. WI 6 — Adaptive Shell và Header.
7. WI 7 — Navigation và Section Routing.
8. WI 8 — Unified Work Item Presentation Model.
9. WI 9 — Reusable Work Item List và Row.
10. WI 10 — Compact Summary Strip.
11. WI 11 — Overview Action Queue.
12. WI 12 — Merge Requests và Reviews Sections.
13. WI 13 — Issues Section và Workflow Tabs.
14. WI 14 — Pipelines và Notifications Sections.
15. WI 15 — Accessibility, Performance và Release Hardening.

Không thực hiện WI 10–14 trước WI 9 vì mọi section mới phải dùng common row/list contract. Không xóa compatibility components trong `GitLabComponents.swift` trước khi consumer cuối cùng đã migrate và `rg` xác nhận không còn reference.

## Integration Checkpoints

- Sau WI 4: data/state foundation review; full `swift test`.
- Sau WI 7: shell/navigation review tại 720, 960, 1440; full `swift test`.
- Sau WI 10: product review cho header/navigation/summary trước khi triển khai toàn bộ sections.
- Sau WI 11: product review cho Overview action-first hierarchy.
- Sau WI 14: feature-complete review; full `swift test` và `swift build`.
- Sau WI 15: release acceptance.

## Completion Criteria

- Mười lăm Work Items được hoàn thành theo dependency order.
- Không còn card layout cũ hoặc dead component references.
- Summary, action queue và từng section dùng cùng scope/count semantics.
- Issue workflow tests giữ nguyên hành vi đã duyệt.
- Partial GitLab failure không xóa dữ liệu thành công hoặc dữ liệu cũ còn dùng được.
- Giao diện hoạt động ở light/dark và widths 720, 960, 1440.
- Keyboard, VoiceOver, contrast và Reduce Motion verification pass.
- `swift build` và `swift test` pass.
- Verification document và PR/MR notes hoàn chỉnh.
