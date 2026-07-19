# Dev Room Testing Label Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đổi workflow stage sai `Test` thành `Testing` đồng bộ từ GitLab label, enum nội bộ, tiêu đề UI và regression tests.

**Architecture:** Giữ nguyên pipeline GitLab → `DevRoomWorkflowStage.stage(for:)` → aggregation → ViewModel/UI. Chỉ đổi canonical stage case và label ở seam domain hiện có; không thêm alias cho `Test`, không đổi service/query hoặc layout.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

## Global Constraints

- Canonical GitLab label là `Testing`; label `Test` không hợp lệ và không có compatibility fallback.
- Enum canonical là `DevRoomWorkflowStage.testing`; không giữ deprecated `.test` alias.
- Thứ tự stage giữ nguyên: `Todo`, `Doing`, `ToTest`, `Testing`, `Passed`.
- GitLab testing tab tiếp tục lọc `Testing` hoặc `ToTest`, nhưng tiêu đề tab đổi thành `Testing`.
- Không đổi project `social/socom-issues`, open-issue query, assignee, member allowlist, màu stage, drawer, animation hoặc layout.
- Worktree đang có thay đổi Dev Room được user duyệt nhưng chưa commit; không stage hoặc commit file source/test trong task này.

---

### Task 1: Rename canonical testing stage and harden label regression

**Files:**
- Modify: `Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Tests/OpsHubTests/DevRoomAggregationTests.swift`
- Modify: `Tests/OpsHubTests/DevRoomViewModelTests.swift`
- Modify: `Tests/OpsHubTests/DevRoomViewTests.swift`
- Modify: `Tests/OpsHubTests/GitLabIssueTabTests.swift`

**Interfaces:**
- Consumes: `DevRoomWorkflowStage.stage(for labels: [String]) -> DevRoomWorkflowStage?`, `GitLabIssueTab.includes(_:) -> Bool`.
- Produces: canonical `DevRoomWorkflowStage.testing`, visible title `Testing`, strict `Testing` label matching.

- [ ] **Step 1: Write the failing domain and tab tests**

In `DevRoomAggregationTests`, update canonical expectations and explicitly reject the old label:

```swift
func testStageMatchingNormalizesCaseAndWhitespace() {
    XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" TODO "]), .todo)
    XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["doing"]), .doing)
    XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["toTEST"]), .toTest)
    XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" testing "]), .testing)
    XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["PASSED"]), .passed)
}

func testLegacyTestLabelIsNotAWorkflowStage() {
    XCTAssertNil(DevRoomWorkflowStage.stage(for: ["Test"]))
}
```

Update all Dev Room fixtures that represent the fourth valid stage from `labels: ["Test"]` to `labels: ["Testing"]`, and all enum references from `.test` to `.testing`. Keep `"Test"` only in `testLegacyTestLabelIsNotAWorkflowStage`.

In `GitLabIssueTabTests`, assert the corrected visible title without changing its filter contract:

```swift
func testTestingTabUsesCanonicalTitle() {
    XCTAssertEqual(GitLabIssueTab.testing.rawValue, "Testing")
}

func testTestingTabIncludesTestingOrToTestLabels() {
    XCTAssertTrue(GitLabIssueTab.testing.includes(makeIssue(labels: ["Testing"])))
    XCTAssertTrue(GitLabIssueTab.testing.includes(makeIssue(labels: ["ToTest"])))
    XCTAssertFalse(GitLabIssueTab.testing.includes(makeIssue(labels: ["Test"])))
    XCTAssertFalse(GitLabIssueTab.testing.includes(makeIssue(labels: ["Passed"])))
}
```

- [ ] **Step 2: Run focused tests and confirm the new contract fails before implementation**

Run:

```bash
swift test --filter DevRoomAggregationTests
swift test --filter GitLabIssueTabTests
```

Expected before implementation: compile failure because `.testing` does not exist and/or title assertion returns `Test`.

- [ ] **Step 3: Implement the canonical enum and label mapping**

Update `DevRoomWorkflowStage`:

```swift
enum DevRoomWorkflowStage: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case todo
    case doing
    case toTest
    case testing
    case passed

    var title: String {
        switch self {
        case .todo: "Todo"
        case .doing: "Doing"
        case .toTest: "ToTest"
        case .testing: "Testing"
        case .passed: "Passed"
        }
    }

    static func stage(for labels: [String]) -> Self? {
        let stages = labels.compactMap { label -> Self? in
            switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "todo": .todo
            case "doing": .doing
            case "totest": .toTest
            case "testing": .testing
            case "passed": .passed
            default: nil
            }
        }
        return stages.max(by: { $0.rawValue < $1.rawValue })
    }
}
```

Update the stage color switch from `case .test` to `case .testing` without changing the existing purple color.

Update the GitLab issue tab title only:

```swift
case testing = "Testing"
```

- [ ] **Step 4: Mechanically migrate all compile-time references and canonical fixtures**

Replace `.test` with `.testing` in Dev Room source/tests. Replace workflow fixture label `"Test"` with `"Testing"`, except the explicit negative regression input.

Run:

```bash
rg -n '\.test\b|case test\b' Sources/OpsHub/Features/DevRoom Tests/OpsHubTests
rg -n '"Test"' Sources/OpsHub/Features/DevRoom Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift Tests/OpsHubTests
```

Expected: no `.test`/`case test`; the only intentional workflow `"Test"` occurrence is the negative regression assertion/input.

- [ ] **Step 5: Run focused regression families**

Run:

```bash
swift test --filter DevRoomAggregationTests
swift test --filter DevRoomViewModelTests
swift test --filter DevRoomViewTests
swift test --filter GitLabIssueTabTests
```

Expected: all pass; filtering, totals, representative stage and drawer grouping use `.testing`.

- [ ] **Step 6: Run completion gates**

Run:

```bash
swift test
swift build -c release
git diff --check
```

Expected: all tests pass, Release build succeeds, and diff check is clean.

- [ ] **Step 7: Audit exact task diff without staging unrelated work**

Run:

```bash
git diff -- Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift Tests/OpsHubTests/DevRoomAggregationTests.swift Tests/OpsHubTests/DevRoomViewModelTests.swift Tests/OpsHubTests/DevRoomViewTests.swift Tests/OpsHubTests/GitLabIssueTabTests.swift
```

Expected: only the approved `Test` → `Testing` contract changes plus existing pre-task unstaged changes in overlapping Dev Room files. Do not stage or commit these files in this task.
