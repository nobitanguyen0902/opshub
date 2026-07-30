# Dashboard Milestone Link and Inspector Dismiss Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm liên kết mở milestone GitLab đang chọn và cho phép bấm ngoài Member Progress Drawer để đóng nhanh.

**Architecture:** Mở rộng model milestone bằng URL tùy chọn được ánh xạ trực tiếp từ GitLab API, sau đó hiển thị action cạnh picker dựa trên capability này. Drawer dùng backdrop theo pattern đang có ở Dev Room; backdrop và Drawer nằm trong cùng `ZStack` để chỉ thao tác ngoài Drawer mới đóng selection.

**Tech Stack:** Swift 6, SwiftUI, XCTest, GitLab REST API.

## Global Constraints

- Không tự dựng URL milestone từ host hoặc project path; chỉ dùng `web_url` do GitLab trả về.
- Milestone thiếu URL vẫn tải và chọn bình thường.
- Giữ nguyên nút X, phím Escape, kích thước, nội dung và animation của Drawer.
- Không thay đổi request, bộ lọc milestone, aggregation hoặc auto-refresh.
- Không commit, push hoặc mở PR nếu người dùng chưa yêu cầu rõ.

---

### Task 1: Preserve GitLab milestone web URL

**Files:**
- Modify: `Sources/OpsHub/Features/Dashboard/Models/SprintDashboardModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Modify: `Tests/OpsHubTests/SprintDashboardAggregationTests.swift`
- Modify: `Tests/OpsHubTests/SprintDashboardViewModelTests.swift`

**Interfaces:**
- Consumes: `GitLabMilestone.webUrl: URL?` từ REST response hiện có.
- Produces: `SprintMilestone.webURL: URL?`.

- [ ] **Step 1: Siết test mapping trước production code**

Thêm `web_url` cho milestone `id = 31` trong fixture và assertion:

```swift
XCTAssertEqual(
    milestones.first?.webURL,
    URL(string: "https://gitlab.example.com/social/socom-issues/-/milestones/31")
)
XCTAssertNil(milestones.last?.webURL)
```

- [ ] **Step 2: Chạy test để xác nhận failure**

Run:

```bash
swift test --filter GitLabServiceTests/testSprintMilestonesLoadsEveryPageAndSkipsIncompleteItems
```

Expected: compile fail vì `SprintMilestone` chưa có `webURL`.

- [ ] **Step 3: Mở rộng model và service mapping tối thiểu**

Thêm field:

```swift
struct SprintMilestone: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let startDate: Date
    let dueDate: Date
    let webURL: URL?
}
```

Ánh xạ trong `GitLabService.sprintMilestones`:

```swift
return SprintMilestone(
    id: milestone.id,
    title: title,
    startDate: startDate,
    dueDate: dueDate,
    webURL: milestone.webUrl
)
```

Cập nhật hai test helper tạo `SprintMilestone` với `webURL: nil`.

- [ ] **Step 4: Chạy focused model/service tests**

Run:

```bash
swift test --filter GitLabServiceTests/testSprintMilestonesLoadsEveryPageAndSkipsIncompleteItems
swift test --filter SprintDashboardAggregationTests
swift test --filter SprintDashboardViewModelTests
```

Expected: tất cả pass.

### Task 2: Add milestone action and click-outside dismissal

**Files:**
- Modify: `Sources/OpsHub/Shared/Components/DashboardView.swift`
- Modify: `Tests/OpsHubTests/SprintDashboardMemberInspectorTests.swift`

**Interfaces:**
- Consumes: `SprintMilestone.webURL: URL?` từ Task 1 và `DashboardView.openURL`.
- Produces: `SprintDashboardMilestonePresentation.canOpen(_:) -> Bool` dùng chung cho trạng thái nút và test.

- [ ] **Step 1: Viết test trạng thái capability của milestone link**

Thêm test tạo hai milestone có và không có URL:

```swift
func testMilestoneLinkRequiresGitLabWebURL() {
    let linked = SprintMilestone(
        id: 31,
        title: "Sprint 31",
        startDate: .distantPast,
        dueDate: .distantFuture,
        webURL: URL(string: "https://gitlab.example.com/milestones/31")
    )
    let unavailable = SprintMilestone(
        id: 30,
        title: "Sprint 30",
        startDate: .distantPast,
        dueDate: .distantFuture,
        webURL: nil
    )

    XCTAssertTrue(SprintDashboardMilestonePresentation.canOpen(linked))
    XCTAssertFalse(SprintDashboardMilestonePresentation.canOpen(unavailable))
}
```

- [ ] **Step 2: Chạy test để xác nhận failure**

Run:

```bash
swift test --filter SprintDashboardMemberInspectorTests/testMilestoneLinkRequiresGitLabWebURL
```

Expected: compile fail vì `SprintDashboardMilestonePresentation` chưa tồn tại.

- [ ] **Step 3: Thêm presentation helper và action cạnh picker**

Thêm helper:

```swift
enum SprintDashboardMilestonePresentation {
    static func canOpen(_ milestone: SprintMilestone?) -> Bool {
        milestone?.webURL != nil
    }
}
```

Trong control group của header, đặt nút external-link giữa picker và divider:

```swift
Button {
    if let webURL = viewModel.selectedMilestone?.webURL {
        openURL(webURL)
    }
} label: {
    Image(systemName: "arrow.up.right.square")
        .frame(width: 42, height: 42)
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
.disabled(
    SprintDashboardMilestonePresentation.canOpen(
        viewModel.selectedMilestone
    ) == false
)
.accessibilityLabel("Open selected milestone in GitLab")
.accessibilityHint("Opens the milestone details in your browser")
```

- [ ] **Step 4: Thêm backdrop đóng Drawer**

Đổi `inspectorOverlay(for:)` sang `ZStack(alignment: .trailing)` theo pattern Dev Room:

```swift
ZStack(alignment: .trailing) {
    Color.black.opacity(0.22)
        .contentShape(Rectangle())
        .onTapGesture(perform: closeInspector)
        .accessibilityHidden(true)

    SprintDashboardMemberInspector(
        summary: summary,
        onClose: closeInspector
    )
    // Giữ nguyên frame, background, accent border và placement hiện có.
}
```

Drawer phải nằm sau backdrop trong source để có z-order cao hơn và không truyền tap bên trong xuống backdrop.

- [ ] **Step 5: Chạy focused Dashboard tests**

Run:

```bash
swift test --filter SprintDashboardMemberInspectorTests
swift test --filter SprintDashboardViewModelTests
```

Expected: tất cả pass.

### Task 3: Full verification and scope review

**Files:**
- Verify all modified source, test and design/plan files.

**Interfaces:**
- Consumes: Task 1 và Task 2 đã pass focused tests.
- Produces: xác minh toàn package ở debug/release và diff sạch lỗi whitespace.

- [ ] **Step 1: Chạy full test và build**

Run:

```bash
swift test
swift build
swift build -c release
```

Expected: tất cả exit code `0`.

- [ ] **Step 2: Kiểm tra diff**

Run:

```bash
git diff --check
git status --short
git diff -- Sources/OpsHub Tests/OpsHubTests
```

Expected: không có whitespace error; chỉ các file trong phạm vi feature bị thay đổi ngoài file trạng thái Xcode có sẵn của người dùng.

- [ ] **Step 3: Bàn giao không commit**

Báo ngắn gọn hành vi đã thêm, file bị ảnh hưởng, lệnh test/build đã chạy và giới hạn còn lại. Không stage hoặc commit.
