# GitLab Pipeline Group Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Chỉ tải Pipeline từ project thuộc top-level group `social`, `Hara AI` hoặc `harasocial`, bao gồm mọi subgroup.

**Architecture:** Giữ project catalog dùng chung không đổi và thêm một predicate riêng cho Pipeline trong `GitLabService`. Predicate đọc segment đầu tiên của `name_with_namespace`; `pipelineBatch(scope:)` kết hợp predicate này với project scope hiện tại trước giới hạn năm project và trước khi gọi API Pipeline.

**Tech Stack:** Swift 6, Swift Package Manager, XCTest.

## Global Constraints

- Chỉ rule tải Pipeline thay đổi; Merge Requests, Reviews, Issues, Notifications và danh sách project không bị lọc.
- Trim khoảng trắng quanh segment và so sánh top-level group không phân biệt hoa thường.
- Nhận project trực tiếp và project trong subgroup.
- Không nhận tên gần giống như `social-tools` hoặc group hợp lệ xuất hiện ở segment không phải đầu tiên.
- Project thiếu `name_with_namespace` không được tải Pipeline.
- Không refactor ngoài phạm vi và không commit nếu người dùng chưa yêu cầu.

---

## File Structure

- `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`: chứa allowlist group, predicate xác định project hợp lệ và áp dụng predicate khi tạo Pipeline batch.
- `Tests/OpsHubTests/GitLabServiceTests.swift`: regression coverage cho direct group, subgroup, tên gần giống, group không liên quan và cập nhật fixture Pipeline cũ theo contract mới.

### Task 1: Lọc project trước khi tải Pipeline

**Files:**

- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift:303-344`
- Test: `Tests/OpsHubTests/GitLabServiceTests.swift:419-525`

**Interfaces:**

- Consumes: `GitLabProject.nameWithNamespace: String?`, `GitLabProjectScope.includes(projectName:)`.
- Produces: `GitLabService.isPipelineProject(_:) -> Bool`, được dùng riêng bởi `pipelineBatch(scope:)`.

- [ ] **Step 1: Viết regression test đang fail**

Thêm test vào `GitLabServiceTests` với catalog gồm project trực tiếp, project trong subgroup, tên group gần giống và group không liên quan:

```swift
func testPipelinesOnlyLoadFromAllowedTopLevelGroupsIncludingSubgroups() async throws {
    let httpClient = StubGitLabHTTPClient(responses: [
        "/api/v4/projects": StubHTTPResponse(
            statusCode: 200,
            body: """
            [
              {"id":7,"name":"direct","name_with_namespace":"social / direct"},
              {"id":8,"name":"nested","name_with_namespace":"Hara AI / platform / nested"},
              {"id":9,"name":"legacy","name_with_namespace":"harasocial / team / legacy"},
              {"id":10,"name":"similar","name_with_namespace":"social-tools / similar"},
              {"id":11,"name":"unrelated","name_with_namespace":"other / social / unrelated"}
            ]
            """
        ),
        "/api/v4/projects/7/pipelines": StubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":7001,"project_id":7,"ref":"main","status":"success"}]"#
        ),
        "/api/v4/projects/8/pipelines": StubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":8001,"project_id":8,"ref":"main","status":"success"}]"#
        ),
        "/api/v4/projects/9/pipelines": StubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":9001,"project_id":9,"ref":"main","status":"success"}]"#
        )
    ])
    let service = GitLabService(
        settingsStore: StaticGitLabSettingsStore(),
        httpClient: httpClient
    )

    let pipelines = try await service.pipelines()

    XCTAssertEqual(pipelines.map(\.id), [9001, 8001, 7001])
    XCTAssertEqual(
        httpClient.requests.compactMap { $0.url?.path }.sorted(),
        [
            "/api/v4/projects",
            "/api/v4/projects/7/pipelines",
            "/api/v4/projects/8/pipelines",
            "/api/v4/projects/9/pipelines"
        ]
    )
}
```

- [ ] **Step 2: Chạy test để xác nhận baseline fail**

Run:

```bash
swift test --filter GitLabServiceTests/testPipelinesOnlyLoadFromAllowedTopLevelGroupsIncludingSubgroups
```

Expected: FAIL vì implementation hiện tại vẫn tạo request cho project `social-tools/similar` và `other/social/unrelated`, làm request set khác expectation.

- [ ] **Step 3: Thêm predicate tối thiểu và áp dụng trước `prefix(5)`**

Trong `GitLabService`, thêm allowlist và helper:

```swift
private static let pipelineTopLevelGroups: Set<String> = [
    "social",
    "hara ai",
    "harasocial"
]

private func isPipelineProject(_ project: GitLabProject) -> Bool {
    guard let nameWithNamespace = project.nameWithNamespace,
          let topLevelGroup = nameWithNamespace.split(
              separator: "/",
              maxSplits: 1
          ).first else {
        return false
    }

    return Self.pipelineTopLevelGroups.contains(
        topLevelGroup
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    )
}
```

Kết hợp helper với scope hiện tại:

```swift
let projects = loadedProjects.filter { project in
    isPipelineProject(project)
        && scope.includes(projectName: projectDisplayName(project))
}
```

- [ ] **Step 4: Cập nhật fixture Pipeline cũ theo contract mới**

Trong `testPipelinesLoadFromRecentMembershipProjects`, đổi:

```swift
"name_with_namespace": "ops/opshub"
```

thành:

```swift
"name_with_namespace": "social/opshub"
```

và cập nhật expectation project thành `social/opshub`.

Trong `testPipelineBatchKeepsSuccessfulProjectsAndReportsPartialFailures`, đổi hai project thành:

```swift
"name_with_namespace": "social/opshub"
"name_with_namespace": "Hara AI/private-service"
```

Sau đó cập nhật expectation `batch.pipelines.first?.project`, `batch.failedProjects` theo hai namespace mới. Giữ nguyên expectation về partial success và hai request Pipeline.

- [ ] **Step 5: Chạy toàn bộ test GitLab service**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: PASS, bao gồm regression test mới và các test partial failure/cache hiện có.

- [ ] **Step 6: Chạy xác minh repository**

Run:

```bash
swift test
swift build
git diff --check
git status --short
```

Expected: toàn bộ test và build PASS; `git diff --check` không có lỗi whitespace; status chỉ chứa design, plan, service và test thuộc phạm vi thay đổi.

- [ ] **Step 7: Review diff và bàn giao**

Kiểm tra:

```bash
git diff -- \
  Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift \
  Tests/OpsHubTests/GitLabServiceTests.swift \
  docs/superpowers/specs/2026-07-27-gitlab-pipeline-group-filter-design.md \
  docs/superpowers/plans/2026-07-27-gitlab-pipeline-group-filter.md
```

Xác nhận rule chỉ áp dụng cho Pipeline, không có thay đổi contract/service khác và không commit.
