# GitLab Merge Request Participant UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hiển thị avatar author cạnh tên project và avatar assignee đầu tiên tại vùng participant cũ trên Merge Requests và Reviews.

**Architecture:** `GitLabService` ánh xạ `assignees.first` vào domain MR bên cạnh author đã có. Presentation tách author khỏi participants: author phục vụ metadata cạnh project, participants chỉ chứa assignee đầu tiên; row dùng avatar component hiện có với kích thước nhỏ cho author và giữ kích thước chuẩn cho assignee.

**Tech Stack:** Swift 5.10, SwiftUI, XCTest, GitLab REST API v4.

## Global Constraints

- Không thay đổi union `assigned_to_me` và `created_by_me` đã triển khai cho Merge Requests.
- `Reviews` tiếp tục chỉ dùng `scope=reviews_for_me`.
- Chỉ dùng `GitLabRESTMergeRequest.assignees.first`; không hiển thị các assignee tiếp theo.
- Không hiển thị text `Requested by`.
- Không đổi presentation của Issue, Pipeline và Notification.
- Không thêm GitLab API request hoặc dependency.
- Không commit, push hoặc mở PR khi người dùng chưa yêu cầu.

---

## File Structure

- `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`: lưu assignee đầu tiên trong domain MR.
- `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`: map `assignees.first` từ REST payload.
- `Tests/OpsHubTests/GitLabServiceTests.swift`: chứng minh service chỉ map assignee đầu tiên.
- `Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift`: tách author khỏi assignee participant và accessibility copy.
- `Sources/OpsHub/Features/GitLab/Components/GitLabAvatarGroup.swift`: hỗ trợ kích thước avatar tùy chọn, giữ default hiện tại.
- `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`: đặt author avatar cạnh project và assignee avatar ở vị trí cũ.
- `Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift`: kiểm tra author/assignee không bị đảo vai trò trên MR và Review.

### Task 1: Map assignee đầu tiên vào domain Merge Request

**Files:**

- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`

**Interfaces:**

- Produces: `GitLabMergeRequest.assigneeName: String?`.
- Produces: `GitLabMergeRequest.assigneeAvatarURL: URL?`.
- Consumes: `GitLabRESTMergeRequest.assignees.first`.

- [ ] **Step 1: Viết regression assertion cho assignee đầu tiên**

Trong fixture của `testMergeRequestsLoadsAssignedOpenItemsFromGitLabAPI`, thêm:

```json
"assignees": [
  {
    "id": 11,
    "username": "first-assignee",
    "name": "First Assignee",
    "avatar_url": "https://gitlab.example.com/uploads/first-assignee.png"
  },
  {
    "id": 12,
    "username": "second-assignee",
    "name": "Second Assignee",
    "avatar_url": "https://gitlab.example.com/uploads/second-assignee.png"
  }
]
```

Thêm assertion:

```swift
XCTAssertEqual(mergeRequests.first?.assigneeName, "First Assignee")
XCTAssertEqual(
    mergeRequests.first?.assigneeAvatarURL?.absoluteString,
    "https://gitlab.example.com/uploads/first-assignee.png"
)
```

- [ ] **Step 2: Chạy service test để xác nhận baseline không compile**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: compile fail vì `GitLabMergeRequest` chưa có `assigneeName` và `assigneeAvatarURL`.

- [ ] **Step 3: Mở rộng domain model với default tương thích**

Trong `GitLabMergeRequest`, thêm stored properties và initializer arguments:

```swift
let assigneeName: String?
let assigneeAvatarURL: URL?
```

```swift
assigneeName: String? = nil,
assigneeAvatarURL: URL? = nil,
```

Gán trong initializer:

```swift
self.assigneeName = assigneeName
self.assigneeAvatarURL = assigneeAvatarURL
```

Default `nil` giữ nguyên toàn bộ fixture/caller hiện có.

- [ ] **Step 4: Map riêng phần tử assignee đầu tiên**

Trong `mapMergeRequest`:

```swift
assigneeName: mergeRequest.assignees.first?.name
    ?? mergeRequest.assignees.first?.username,
assigneeAvatarURL: mergeRequest.assignees.first?.avatarUrl,
```

- [ ] **Step 5: Chạy service tests**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: toàn bộ `GitLabServiceTests` pass và assertion chỉ nhận assignee đầu tiên.

### Task 2: Tách author và assignee trong presentation

**Files:**

- Modify: `Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift`

**Interfaces:**

- Produces: `GitLabWorkItemPresentation.author: GitLabWorkItemParticipant?`.
- Preserves: `GitLabWorkItemPresentation.participants: [GitLabWorkItemParticipant]`.
- Consumes: author và assignee fields của `GitLabMergeRequest`.

- [ ] **Step 1: Viết regression test chứng minh hai vai trò tách biệt**

Trong test MR hiện có, truyền thêm:

```swift
assigneeName: "Merge Owner",
assigneeAvatarURL: URL(string: "https://gitlab.example.com/assignee.png"),
```

Thay assertion role cũ bằng:

```swift
XCTAssertEqual(item.author?.name, "Octo Cat")
XCTAssertEqual(item.author?.avatarURL?.absoluteString, "https://gitlab.example.com/avatar.png")
XCTAssertEqual(item.participants.map(\.name), ["Merge Owner"])
XCTAssertTrue(item.accessibilitySummary.contains("Author Octo Cat"))
XCTAssertTrue(item.accessibilitySummary.contains("Assigned to Merge Owner"))
```

Test Review cũng truyền author và assignee khác nhau rồi xác nhận:

```swift
XCTAssertEqual(item.author?.name, "Review Author")
XCTAssertEqual(item.participants.map(\.name), ["Review Assignee"])
```

Test dữ liệu rỗng xác nhận:

```swift
XCTAssertNil(item.author)
XCTAssertTrue(item.participants.isEmpty)
```

- [ ] **Step 2: Chạy presentation tests để xác nhận baseline thất bại**

Run:

```bash
swift test --filter GitLabWorkItemPresentationTests
```

Expected: compile fail vì presentation chưa có `author`; participants hiện vẫn chứa author.

- [ ] **Step 3: Đơn giản hóa participant và thêm author riêng**

Đưa `GitLabWorkItemParticipant` về dữ liệu identity thuần:

```swift
struct GitLabWorkItemParticipant: Hashable, Sendable {
    let name: String
    let avatarURL: URL?
}
```

Thêm vào presentation:

```swift
let author: GitLabWorkItemParticipant?
```

Tạo helper chuẩn hóa:

```swift
private static func participant(
    name: String?,
    avatarURL: URL?
) -> GitLabWorkItemParticipant? {
    guard let name else { return nil }
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedName.isEmpty == false else { return nil }
    return GitLabWorkItemParticipant(name: normalizedName, avatarURL: avatarURL)
}
```

MR mapping:

```swift
author = Self.participant(
    name: mergeRequest.authorName,
    avatarURL: mergeRequest.authorAvatarURL
)
participants = [
    Self.participant(
        name: mergeRequest.assigneeName,
        avatarURL: mergeRequest.assigneeAvatarURL
    )
].compactMap { $0 }
```

Issue, Pipeline và Notification gán `author = nil` và giữ mapping participants hiện tại qua helper mới.

- [ ] **Step 4: Phân biệt vai trò trong accessibility summary**

Thêm author text và chỉ gắn nhãn assignee cho MR/Review:

```swift
let authorText = author.map { "Author \($0.name)" }
let participantText: String
switch kind {
case .mergeRequest, .review:
    participantText = participants
        .map { "Assigned to \($0.name)" }
        .joined(separator: ", ")
case .issue, .pipeline, .notification:
    participantText = participants.map(\.name).joined(separator: ", ")
}
```

Đưa `authorText` và `participantText` không rỗng vào summary. Không dùng copy `Requested by`; accessibility của Issue, Pipeline và Notification giữ nguyên.

- [ ] **Step 5: Chạy presentation tests**

Run:

```bash
swift test --filter GitLabWorkItemPresentationTests
```

Expected: tất cả presentation tests pass, MR/Review tách đúng author và assignee.

### Task 3: Đặt avatar đúng vị trí trên row

**Files:**

- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabAvatarGroup.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`

**Interfaces:**

- Consumes: `GitLabWorkItemPresentation.author`.
- Consumes: `GitLabWorkItemPresentation.participants`.
- Produces: `GitLabAvatarGroup.avatarSize: CGFloat` với default `30`.

- [ ] **Step 1: Cho phép avatar group dùng kích thước nhỏ**

Trong `GitLabAvatarGroup`:

```swift
let participants: [GitLabWorkItemParticipant]
var avatarSize: CGFloat = 30
```

Thay frame cứng của avatar và overflow indicator bằng:

```swift
.frame(width: avatarSize, height: avatarSize)
```

Default `30` giữ nguyên mọi consumer hiện tại.

- [ ] **Step 2: Render author avatar cạnh project**

Thay `Text(item.project)` bằng:

```swift
HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
    Text(item.project)
        .font(.system(.caption, design: .monospaced))
        .foregroundStyle(.secondary)
        .lineLimit(1)

    if let author = item.author {
        GitLabAvatarGroup(participants: [author], avatarSize: 18)
            .help("Author: \(author.name)")
    }
}
```

- [ ] **Step 3: Giữ vị trí cũ cho assignee và bỏ text requester**

Trong `participantAndTime` giữ:

```swift
if item.participants.isEmpty == false {
    GitLabAvatarGroup(participants: item.participants)
}
```

Xóa toàn bộ `Text(participant.displayName)` và điều kiện `participant.role`.

- [ ] **Step 4: Build để kiểm tra SwiftUI**

Run:

```bash
swift build
```

Expected: build pass; API avatar mới không phá các call site hiện có.

### Task 4: Xác minh toàn bộ thay đổi

**Files:**

- Verify only: toàn bộ working tree.

**Interfaces:**

- Consumes: kết quả Task 1-3.
- Produces: bằng chứng test/build/diff sạch.

- [ ] **Step 1: Chạy targeted tests**

Run:

```bash
swift test --filter GitLabServiceTests
swift test --filter GitLabWorkItemPresentationTests
```

Expected: cả hai test suite pass.

- [ ] **Step 2: Chạy full suite và release build**

Run:

```bash
swift test
swift build -c release
```

Expected: toàn bộ tests và release build pass.

- [ ] **Step 3: Kiểm tra diff và phạm vi**

Run:

```bash
git diff --check
git status --short
git diff -- Sources/OpsHub/Features/GitLab/Models/GitLabModels.swift \
  Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift \
  Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift \
  Sources/OpsHub/Features/GitLab/Components/GitLabAvatarGroup.swift \
  Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift \
  Tests/OpsHubTests/GitLabServiceTests.swift \
  Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift
```

Expected: không có whitespace error; chỉ source, test và docs đã duyệt nằm trong diff, ngoài file Xcode state có sẵn của người dùng.
