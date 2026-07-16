# GitLab Doing Issue Tab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm tab GitLab Issues `Doing` ngay sau `Assign me`, lọc issue của workflow project có label `Doing` mà không thay đổi UI hoặc cách fetch API hiện tại.

**Architecture:** Mở rộng enum `GitLabIssueTab`, vì `GitLabIssuesView` đã render trực tiếp `allCases` và ViewModel đã dùng `includes(_:)` làm seam lọc chung. Rule mới chỉ kiểm tra `isWorkflowProject` và label đã chuẩn hóa, nên toàn bộ service, request GitLab, phân trang, merge dữ liệu và SwiftUI list tiếp tục được tái sử dụng nguyên trạng.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

## Global Constraints

- Thứ tự tab phải là `Assign me`, `Doing`, `Test`, `Passed`, `Build`, `Bug Pro`.
- Tab `Doing` chỉ nhận issue thuộc workflow project `social/socom-issues` có label `Doing`.
- Label được so khớp không phân biệt chữ hoa, chữ thường và bỏ khoảng trắng thừa.
- Tab `Doing` không yêu cầu issue được assign cho người dùng hiện tại.
- Không thay đổi UI, service, request API, project scope, phân trang, merge dữ liệu, điều kiện issue đang mở hoặc giới hạn cập nhật một tháng.
- Không thay đổi rule của năm tab hiện tại.

---

## File Map

- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift` — regression coverage cho label, project scope và thứ tự tab.
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift` — khai báo case `doing` và rule lọc tại seam `GitLabIssueTab.includes(_:)`.
- No change: `Sources/OpsHub/Features/GitLab/Views/GitLabIssuesView.swift` — `ForEach(GitLabIssueTab.allCases)` tự render tab mới.
- No change: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift` — tiếp tục fetch, phân trang và merge cùng tập issue hiện tại.

### Task 1: Add the Doing workflow tab with regression coverage

**Files:**
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift:10`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift:397-420`

**Interfaces:**
- Consumes: `GitLabIssueTab.allCases`, `GitLabIssueTab.includes(_ issue: GitLabIssue) -> Bool`, `GitLabIssue.isWorkflowProject`, `GitLabIssue.labels`.
- Produces: `GitLabIssueTab.doing` với raw value `Doing`; `includes(_:)` trả về `true` khi issue thuộc workflow project và tập label chuẩn hóa chứa `doing`.

- [ ] **Step 1: Write the failing tests**

Chèn các test sau ngay sau `testAssignedToMeTabIncludesEveryLoadedIssue()` trong `Tests/OpsHubTests/GitLabIssueTabTests.swift`:

```swift
func testDoingTabIncludesWorkflowProjectIssueWithDoingLabel() {
    XCTAssertTrue(GitLabIssueTab.doing.includes(makeIssue(labels: ["Doing"])))
    XCTAssertFalse(GitLabIssueTab.doing.includes(makeIssue(labels: ["Testing"])))
}

func testDoingTabLabelMatchingIsCaseInsensitiveAndTrimsWhitespace() {
    XCTAssertTrue(GitLabIssueTab.doing.includes(makeIssue(labels: [" DOING "])))
}

func testDoingTabExcludesIssuesFromOtherProjects() {
    let issue = makeIssue(labels: ["Doing"], isWorkflowProject: false)

    XCTAssertFalse(GitLabIssueTab.doing.includes(issue))
}

func testDoingTabAppearsImmediatelyAfterAssignedToMe() {
    XCTAssertEqual(
        GitLabIssueTab.allCases.prefix(2).map(\.rawValue),
        ["Assign me", "Doing"]
    )
}
```

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter GitLabIssueTabTests
```

Expected: build fails because `GitLabIssueTab` has no member `doing`. This proves the tests exercise the missing feature.

- [ ] **Step 3: Implement the minimal enum case and filter rule**

Trong `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`, thêm `doing` ngay sau `assignedToMe` và thêm nhánh switch tương ứng:

```swift
enum GitLabIssueTab: String, CaseIterable, Identifiable, Sendable {
    case assignedToMe = "Assign me"
    case doing = "Doing"
    case testing = "Test"
    case passed = "Passed"
    case build = "Build"
    case productionBug = "Bug Pro"

    var id: Self { self }

    func includes(_ issue: GitLabIssue) -> Bool {
        let labels = Set(issue.labels.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() })

        return switch self {
        case .assignedToMe:
            issue.isAssignedToMe
        case .doing:
            issue.isWorkflowProject && labels.contains("doing")
        case .testing:
            issue.isWorkflowProject && (labels.contains("testing") || labels.contains("totest"))
        case .passed:
            issue.isWorkflowProject && labels.isSuperset(of: ["passed", "toproduction"])
        case .build:
            issue.isWorkflowProject && labels.isSuperset(of: ["passed", "toproduction", "merged"])
        case .productionBug:
            issue.isWorkflowProject && labels.contains("bug production")
        }
    }
}
```

Không sửa `GitLabIssuesView`, `GitLabDashboardViewModel` hoặc `GitLabServices`; chúng đã dùng enum/filter và dữ liệu hiện tại.

- [ ] **Step 4: Run the focused tests and verify they pass**

Run:

```bash
swift test --filter GitLabIssueTabTests
```

Expected: `GitLabIssueTabTests` pass, bao gồm các test cũ và bốn test mới cho `Doing`.

- [ ] **Step 5: Run the full verification gates**

Run:

```bash
swift test
swift build -c release
git diff --check
```

Expected:

- Toàn bộ test suite pass.
- Release build hoàn tất không có compile error.
- `git diff --check` không có output và trả về exit code `0`.

- [ ] **Step 6: Review the scoped diff**

Run:

```bash
git diff -- Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift Tests/OpsHubTests/GitLabIssueTabTests.swift
```

Expected: diff chỉ chứa case/rule `doing` và các regression tests; không có thay đổi service, ViewModel hoặc SwiftUI layout.

- [ ] **Step 7: Commit the implementation**

```bash
git add Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift Tests/OpsHubTests/GitLabIssueTabTests.swift
git commit -m "feat(gitlab): add Doing issue tab"
```
