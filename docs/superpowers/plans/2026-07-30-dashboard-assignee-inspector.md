# Dashboard Assignee Inspector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hiển thị assignee trên production bug và mở Inspector trượt từ phải để xem nhanh sprint task của từng member.

**Architecture:** Giữ GitLab service và request lifecycle hiện tại. Mở rộng presentation data của `SprintDashboardMemberSummary` để mang theo các issue đã dedupe/scope sẵn, sau đó thêm một SwiftUI Inspector độc lập và nối selection cục bộ vào `DashboardView`.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, XCTest, semantic tokens từ `OpsHubTerminalTheme`.

## Global Constraints

- Không thêm API request hoặc thay đổi query GitLab.
- Không thay đổi KPI, release rule, milestone selection hoặc Dev Room member settings.
- Inspector rộng tối đa `460pt`, trượt từ cạnh phải, không có scrim và không khóa Dashboard.
- Hỗ trợ member đã cấu hình và hàng `Unassigned`.
- Task có URL mở GitLab; task thiếu URL vẫn hiển thị nhưng không tương tác.
- Tôn trọng Reduce Motion, keyboard Escape, accessibility focus và light/dark mode.
- Chỉ dùng semantic theme token; không thêm màu hardcode.
- Không commit, push, mở PR hoặc release nếu người dùng chưa yêu cầu rõ.

## File Structure

- Modify `Sources/OpsHub/Features/Dashboard/Models/SprintDashboardModels.swift`
  - Lưu issue trong member summary và cung cấp thứ tự ổn định cho Inspector.
- Modify `Tests/OpsHubTests/SprintDashboardAggregationTests.swift`
  - Regression coverage cho grouping, unassigned, dedupe và sort.
- Create `Sources/OpsHub/Features/Dashboard/Components/SprintDashboardMemberInspector.swift`
  - Layout policy, task presentation, avatar dùng chung và nội dung Inspector.
- Create `Tests/OpsHubTests/SprintDashboardMemberInspectorTests.swift`
  - Test pure presentation/layout/close behavior của Inspector.
- Modify `Sources/OpsHub/Shared/Components/DashboardView.swift`
  - Member-row selection, overlay lifecycle, focus restoration và production-bug avatar.

---

### Task 1: Carry scoped issues in each member summary

**Files:**
- Modify: `Sources/OpsHub/Features/Dashboard/Models/SprintDashboardModels.swift`
- Test: `Tests/OpsHubTests/SprintDashboardAggregationTests.swift`

**Interfaces:**
- Consumes: `[SprintDashboardIssue]` đã dedupe trong `SprintDashboardAggregator.makeData(...)`.
- Produces: `SprintDashboardMemberSummary.init(member:issues:)`, `issues`, computed `ticketCount`, `releasedCount`, `progress`.

- [ ] **Step 1: Add failing aggregation assertions**

Mở rộng `testMemberBreakdownUsesSelectedCurrentAssigneeAndKeepsUnassignedLast` để kiểm tra issue identity:

```swift
XCTAssertEqual(data.memberSummaries[0].issues.map(\.id), [2, 1])
XCTAssertEqual(data.memberSummaries[1].issues.map(\.id), [4])
```

Thêm test cho thứ tự cập nhật và fallback ID:

```swift
func testMemberSummaryIssuesSortByNewestUpdateThenDescendingGlobalID() {
    let alice = member(id: 1, name: "Alice")
    let issues = [
        issue(id: 1, assignee: alice, updatedAt: "2026-07-29T08:00:00+07:00"),
        issue(id: 2, assignee: alice, updatedAt: "2026-07-30T08:00:00+07:00"),
        issue(id: 3, assignee: alice, updatedAt: "2026-07-30T08:00:00+07:00")
    ]

    let data = SprintDashboardAggregator.makeData(
        milestone: currentMilestone,
        sprintIssues: issues,
        productionBugs: [],
        selectedUserIDs: [alice.id],
        calendar: vietnamCalendar
    )

    XCTAssertEqual(data.memberSummaries.first?.issues.map(\.id), [3, 2, 1])
}
```

Trong test dedupe hiện có, bổ sung:

```swift
XCTAssertEqual(data.memberSummaries.first?.issues.map(\.title), ["Current"])
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter SprintDashboardAggregationTests
```

Expected: compile failure vì `SprintDashboardMemberSummary` chưa có `issues`.

- [ ] **Step 3: Replace stored counts with scoped issue data**

Đổi model:

```swift
struct SprintDashboardMemberSummary: Identifiable, Hashable, Sendable {
    let member: SprintDashboardMember?
    let issues: [SprintDashboardIssue]

    var id: String {
        member.map { "member:\($0.id)" } ?? "unassigned"
    }

    var ticketCount: Int { issues.count }

    var releasedCount: Int {
        issues.count(where: SprintDashboardAggregator.isReleased)
    }

    var progress: Double {
        guard ticketCount > 0 else { return 0 }
        return Double(releasedCount) / Double(ticketCount)
    }
}
```

Thêm sort helper ổn định trong aggregator:

```swift
private static func memberIssueSort(
    _ lhs: SprintDashboardIssue,
    _ rhs: SprintDashboardIssue
) -> Bool {
    if lhs.updatedAt != rhs.updatedAt {
        return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
    }
    return lhs.id > rhs.id
}
```

Đổi hai initializer trong `memberSummaries(...)`:

```swift
SprintDashboardMemberSummary(
    member: member,
    issues: issues.sorted(by: memberIssueSort)
)
```

và:

```swift
SprintDashboardMemberSummary(
    member: nil,
    issues: unassignedIssues.sorted(by: memberIssueSort)
)
```

- [ ] **Step 4: Run aggregation tests**

Run:

```bash
swift test --filter SprintDashboardAggregationTests
```

Expected: toàn bộ `SprintDashboardAggregationTests` pass; count/progress assertions cũ vẫn xanh.

---

### Task 2: Build the reusable Inspector presentation and layout

**Files:**
- Create: `Sources/OpsHub/Features/Dashboard/Components/SprintDashboardMemberInspector.swift`
- Create: `Tests/OpsHubTests/SprintDashboardMemberInspectorTests.swift`

**Interfaces:**
- Consumes: `SprintDashboardMemberSummary`, `SprintDashboardIssue`, `OpsHubTerminalTheme`.
- Produces:
  - `SprintDashboardInspectorLayout.placement(for:)`
  - `SprintDashboardIssuePresentation.workflowLabel(for:)`
  - `SprintDashboardIssuePresentation.canOpen(_:)`
  - `SprintMemberAvatar(member:size:)`
  - `SprintDashboardMemberInspector(summary:onClose:)`

- [ ] **Step 1: Add failing tests for layout and issue presentation**

Tạo test file:

```swift
import XCTest
@testable import OpsHub

final class SprintDashboardMemberInspectorTests: XCTestCase {
    func testInspectorUsesPreferredWidthWhenSpaceAllows() {
        let placement = SprintDashboardInspectorLayout.placement(for: 900)
        XCTAssertEqual(placement.width, 460)
        XCTAssertEqual(placement.trailingInset, 0)
    }

    func testInspectorKeepsHorizontalInsetsInNarrowSpace() {
        let placement = SprintDashboardInspectorLayout.placement(for: 400)
        XCTAssertEqual(placement.width, 368)
        XCTAssertEqual(placement.trailingInset, 16)
    }

    func testWorkflowLabelUsesHighestProgressKnownLabel() {
        let issue = SprintDashboardIssue(
            id: 1,
            iid: 10,
            title: "Issue",
            project: "social/socom-issues",
            labels: ["Doing", "Passed", "ToProduction"],
            assignee: nil,
            createdAt: nil,
            updatedAt: nil,
            webURL: nil
        )

        XCTAssertEqual(
            SprintDashboardIssuePresentation.workflowLabel(for: issue),
            "ToProduction"
        )
        XCTAssertFalse(SprintDashboardIssuePresentation.canOpen(issue))
    }

    @MainActor
    func testInspectorCloseInvokesAction() {
        var closeCount = 0
        let inspector = SprintDashboardMemberInspector(
            summary: SprintDashboardMemberSummary(member: nil, issues: []),
            onClose: { closeCount += 1 }
        )

        inspector.close()

        XCTAssertEqual(closeCount, 1)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run:

```bash
swift test --filter SprintDashboardMemberInspectorTests
```

Expected: compile failure vì Inspector types chưa tồn tại.

- [ ] **Step 3: Implement layout and pure presentation helpers**

Trong file component mới:

```swift
import SwiftUI

enum SprintDashboardInspectorLayout {
    static let preferredWidth: CGFloat = 460
    static let horizontalInset: CGFloat = 16

    struct Placement: Equatable {
        let width: CGFloat
        let trailingInset: CGFloat
    }

    static func placement(for availableWidth: CGFloat) -> Placement {
        let boundedWidth = max(0, availableWidth)
        guard boundedWidth < preferredWidth + (horizontalInset * 2) else {
            return Placement(width: preferredWidth, trailingInset: 0)
        }
        let inset = min(horizontalInset, boundedWidth / 2)
        return Placement(
            width: boundedWidth - (inset * 2),
            trailingInset: inset
        )
    }
}

enum SprintDashboardIssuePresentation {
    private static let workflowLabels = [
        "Merged", "ToProduction", "Passed", "Testing", "ToTest", "Doing", "Todo"
    ]

    static func workflowLabel(for issue: SprintDashboardIssue) -> String? {
        workflowLabels.first { expected in
            issue.labels.contains {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(expected) == .orderedSame
            }
        }
    }

    static func canOpen(_ issue: SprintDashboardIssue) -> Bool {
        issue.webURL != nil
    }
}
```

- [ ] **Step 4: Implement reusable avatar**

Tạo `SprintMemberAvatar` trong cùng file:

```swift
struct SprintMemberAvatar: View {
    let member: SprintDashboardMember?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let url = member?.avatarURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(OpsHubTerminalTheme.borderStrong) }
        .accessibilityHidden(true)
    }
}
```

Fallback dùng initials cho member và `person.crop.circle.badge.questionmark` cho `nil`; dùng semantic colors từ theme.

- [ ] **Step 5: Implement Inspector header and task list**

`SprintDashboardMemberInspector`:

- dùng `@Environment(\.openURL)` và `@AccessibilityFocusState`;
- header gồm avatar 44pt, name/username, `releasedCount/ticketCount`, progress và close button;
- `ScrollView` + `LazyVStack` hiển thị `summary.issues`;
- task row hiển thị title, `project #iid`, workflow label, released text/icon và relative `updatedAt`;
- `.disabled(canOpen == false)` nhưng vẫn giữ row hiển thị;
- `.onExitCommand(perform: close)`;
- focus heading khi xuất hiện.

Close interface:

```swift
func close() {
    onClose()
}
```

Task button:

```swift
Button {
    if let webURL = issue.webURL {
        openURL(webURL)
    }
} label: {
    SprintDashboardInspectorTaskRow(issue: issue)
}
.buttonStyle(.plain)
.disabled(SprintDashboardIssuePresentation.canOpen(issue) == false)
.accessibilityHint(
    issue.webURL == nil
        ? "GitLab link is unavailable"
        : "Opens this issue in GitLab"
)
```

- [ ] **Step 6: Run Inspector tests**

Run:

```bash
swift test --filter SprintDashboardMemberInspectorTests
```

Expected: 4 tests pass.

---

### Task 3: Integrate member selection and production-bug assignee

**Files:**
- Modify: `Sources/OpsHub/Shared/Components/DashboardView.swift`
- Test: `Tests/OpsHubTests/SprintDashboardMemberInspectorTests.swift`

**Interfaces:**
- Consumes: `SprintDashboardMemberInspector`, `SprintMemberAvatar`, summary IDs from Task 1.
- Produces: interactive member rows, right-side overlay lifecycle and assignee metadata in production bug rows.

- [ ] **Step 1: Add failing focus-router tests**

Thêm pure focus target/router vào test expectation:

```swift
func testFocusRouterReturnsToMemberAfterInspectorCloses() {
    XCTAssertEqual(
        SprintDashboardInspectorFocusRouter.target(
            previousSummaryID: "member:41",
            selectedSummaryID: nil,
            displayedSummaryIDs: ["member:41", "unassigned"]
        ),
        "member:41"
    )
}

func testFocusRouterDoesNotReturnToRemovedMember() {
    XCTAssertNil(
        SprintDashboardInspectorFocusRouter.target(
            previousSummaryID: "member:41",
            selectedSummaryID: nil,
            displayedSummaryIDs: ["member:52"]
        )
    )
}
```

- [ ] **Step 2: Run test and verify focus router is missing**

Run:

```bash
swift test --filter SprintDashboardMemberInspectorTests
```

Expected: compile failure vì `SprintDashboardInspectorFocusRouter` chưa tồn tại.

- [ ] **Step 3: Add selection state and focus router**

Trong `DashboardView.swift`:

```swift
enum SprintDashboardInspectorFocusRouter {
    static func target(
        previousSummaryID: String?,
        selectedSummaryID: String?,
        displayedSummaryIDs: Set<String>
    ) -> String? {
        guard selectedSummaryID == nil,
              let previousSummaryID,
              displayedSummaryIDs.contains(previousSummaryID) else {
            return nil
        }
        return previousSummaryID
    }
}
```

Thêm state:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@State private var selectedSummaryID: String?
@AccessibilityFocusState private var focusedSummaryID: String?
```

Computed selection phải resolve từ `viewModel.data?.memberSummaries` mỗi lần render, không lưu copy stale:

```swift
private var selectedSummary: SprintDashboardMemberSummary? {
    guard let selectedSummaryID else { return nil }
    return viewModel.data?.memberSummaries.first { $0.id == selectedSummaryID }
}
```

- [ ] **Step 4: Convert member rows to semantic buttons**

Giữ header row không tương tác. Bọc từng data row trong:

```swift
Button {
    selectedSummaryID = summary.id
} label: {
    memberTableRow(...)
        .contentShape(Rectangle())
}
.buttonStyle(.plain)
.accessibilityFocused($focusedSummaryID, equals: summary.id)
.accessibilityLabel(
    "\(summary.member?.name ?? "Unassigned"), "
        + "\(summary.ticketCount) tickets, "
        + "\(summary.releasedCount) released"
)
.accessibilityHint("Shows this member's sprint tasks")
```

Không đặt button con bên trong member row.

- [ ] **Step 5: Add trailing Inspector overlay**

Tách `ScrollView` hiện tại thành `dashboardScroll` và đổi body content thành:

```swift
ZStack(alignment: .trailing) {
    dashboardScroll

    if let selectedSummary {
        GeometryReader { proxy in
            let placement = SprintDashboardInspectorLayout.placement(
                for: proxy.size.width
            )
            SprintDashboardMemberInspector(
                summary: selectedSummary,
                onClose: closeInspector
            )
            .frame(width: placement.width)
            .frame(maxHeight: .infinity)
            .background(OpsHubTerminalTheme.surfacePrimary)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OpsHubTerminalTheme.accent)
                    .frame(width: 2)
            }
            .padding(.trailing, placement.trailingInset)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .trailing).combined(with: .opacity)
            )
        }
    }
}
.animation(.easeOut(duration: reduceMotion ? 0.12 : 0.20), value: selectedSummaryID)
.onExitCommand(perform: closeInspector)
```

Không thêm scrim hoặc tap-to-dismiss trên Dashboard.

- [ ] **Step 6: Close invalid selection and restore accessibility focus**

Theo dõi danh sách summary ID:

```swift
.onChange(of: viewModel.data?.memberSummaries.map(\.id) ?? []) {
    let displayedIDs = Set(viewModel.data?.memberSummaries.map(\.id) ?? [])
    if let selectedSummaryID, displayedIDs.contains(selectedSummaryID) == false {
        self.selectedSummaryID = nil
    }
}
.onChange(of: selectedSummaryID) { previousID, currentID in
    focusedSummaryID = SprintDashboardInspectorFocusRouter.target(
        previousSummaryID: previousID,
        selectedSummaryID: currentID,
        displayedSummaryIDs: Set(viewModel.data?.memberSummaries.map(\.id) ?? [])
    )
}
```

Close action:

```swift
private func closeInspector() {
    selectedSummaryID = nil
}
```

- [ ] **Step 7: Add assignee avatar to production bug rows**

Ở vùng metadata bên phải của `productionBugRow`:

```swift
SprintMemberAvatar(member: issue.assignee)
    .help(issue.assignee?.name ?? "Unassigned")
```

Giữ avatar bên trong label của production bug button; không tạo nested action. Bổ sung assignee vào accessibility label của row:

```swift
.accessibilityLabel(
    "\(issue.title), \(issue.project) issue \(issue.iid), "
        + "assigned to \(issue.assignee?.name ?? "nobody")"
)
```

Xóa bản `private struct SprintMemberAvatar` cũ ở cuối `DashboardView.swift` sau khi consumer đã chuyển sang component dùng chung.

- [ ] **Step 8: Run focused tests**

Run:

```bash
swift test --filter SprintDashboardAggregationTests
swift test --filter SprintDashboardMemberInspectorTests
swift test --filter SprintDashboardViewModelTests
```

Expected: tất cả focused tests pass.

---

### Task 4: Full verification and scope review

**Files:**
- Verify all files listed above.

**Interfaces:**
- Consumes: completed implementation from Tasks 1–3.
- Produces: verified debug/release-compatible feature with a clean scoped diff.

- [ ] **Step 1: Run full test suite**

Run:

```bash
swift test
```

Expected: all OpsHub tests pass.

- [ ] **Step 2: Run debug build**

Run:

```bash
swift build
```

Expected: build succeeds without warnings introduced by this change.

- [ ] **Step 3: Run release build**

Run:

```bash
swift build -c release
```

Expected: release build succeeds under Swift 6 strict concurrency.

- [ ] **Step 4: Check formatting and whitespace**

Run:

```bash
git diff --check
```

Expected: no whitespace errors.

- [ ] **Step 5: Review scope**

Run:

```bash
git status --short
git diff --stat
git diff -- Sources/OpsHub/Features/Dashboard Sources/OpsHub/Shared/Components/DashboardView.swift Tests/OpsHubTests/SprintDashboardAggregationTests.swift Tests/OpsHubTests/SprintDashboardMemberInspectorTests.swift
```

Expected:

- only Dashboard model/component/view/tests plus approved spec/plan are changed;
- no GitLab request, settings, packaging, Cask or release file changed;
- no commit is created.
