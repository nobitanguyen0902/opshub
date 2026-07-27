# GitLab Merge Request Ownership Implementation Plan

> **UI follow-up:** Task 2 trong plan này đã được thay thế bởi
> `docs/superpowers/plans/2026-07-27-gitlab-merge-request-participant-ui.md`.
> Logic union Merge Requests ở Task 1 vẫn giữ nguyên.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hiển thị cả merge request assign cho người dùng và merge request do người dùng tạo, đồng thời ghi rõ `Requested by <author>` trên Merge Requests và Reviews.

**Architecture:** `GitLabService` tải song song hai scope `assigned_to_me` và `created_by_me`, hợp nhất theo global MR `id`, rồi sắp xếp theo thời gian cập nhật. Presentation gắn role `Requested by` cho author của MR; row render role, tên và avatar từ metadata này mà không thay đổi domain model hoặc endpoint Reviews.

**Tech Stack:** Swift 5.10, Swift Concurrency, SwiftUI, XCTest, GitLab REST API v4.

## Global Constraints

- `Reviews` tiếp tục chỉ dùng `scope=reviews_for_me`.
- Nếu một trong hai request của `Merge Requests` lỗi, toàn bộ lần tải thất bại.
- Không thay đổi filter, thao tác mở GitLab hoặc presentation của Issue, Pipeline và Notification.
- Không thêm dependency hoặc API request ngoài hai scope MR đã chốt.
- Không commit, push hoặc mở PR khi người dùng chưa yêu cầu.

---

## File Structure

- `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`: tải hai scope MR, hợp nhất, chống trùng và sắp xếp.
- `Tests/OpsHubTests/GitLabServiceTests.swift`: regression coverage cho query scope, MR do người dùng tạo, chống trùng, thứ tự và lỗi từng phần.
- `Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift`: gắn role hiển thị cho author MR và đưa role vào accessibility text.
- `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`: render avatar cùng `Requested by <author>`.
- `Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift`: kiểm tra role trên Merge Request/Review và trường hợp thiếu author.

### Task 1: Hợp nhất Merge Requests assign cho tôi và do tôi tạo

**Files:**

- Modify: `Tests/OpsHubTests/GitLabServiceTests.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`

**Interfaces:**

- Consumes: `private func mergeRequests(scope: String) async throws -> [GitLabMergeRequest]`.
- Produces: `func mergeRequests() async throws -> [GitLabMergeRequest]` trả về union đã chống trùng và sắp xếp.
- Preserves: `func mergeReviews() async throws -> [GitLabMergeRequest]` vẫn gọi scope `reviews_for_me`.

- [ ] **Step 1: Viết regression test cho hai scope, MR do tôi tạo, chống trùng và thứ tự**

Thay test `testMergeRequestsLoadsAssignedOpenItemsFromGitLabAPI` bằng fixture riêng cho từng scope:

```swift
func testMergeRequestsCombinesAssignedAndCreatedItemsWithoutDuplicates() async throws {
    let httpClient = StubGitLabHTTPClient(responses: [
        "/api/v4/merge_requests?scope=assigned_to_me": StubHTTPResponse(
            statusCode: 200,
            body: """
            [
              {"id":1001,"iid":41,"title":"Assigned","references":{"full":"ops/opshub!41"},
               "updated_at":"2026-07-27T01:00:00.000Z"},
              {"id":1002,"iid":42,"title":"Both","references":{"full":"ops/opshub!42"},
               "updated_at":"2026-07-27T02:00:00.000Z"}
            ]
            """
        ),
        "/api/v4/merge_requests?scope=created_by_me": StubHTTPResponse(
            statusCode: 200,
            body: """
            [
              {"id":1002,"iid":42,"title":"Both","references":{"full":"ops/opshub!42"},
               "updated_at":"2026-07-27T02:00:00.000Z"},
              {"id":1003,"iid":43,"title":"Created","references":{"full":"ops/opshub!43"},
               "updated_at":"2026-07-27T03:00:00.000Z"}
            ]
            """
        )
    ])
    let service = GitLabService(
        settingsStore: StaticGitLabSettingsStore(),
        httpClient: httpClient
    )

    let mergeRequests = try await service.mergeRequests()

    XCTAssertEqual(mergeRequests.map(\.id), [1003, 1002, 1001])
    let scopes = Set(httpClient.requests.compactMap { request in
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "scope" })?
            .value
    })
    XCTAssertEqual(scopes, ["assigned_to_me", "created_by_me"])
}
```

- [ ] **Step 2: Viết regression test chứng minh không trả dữ liệu thiếu**

```swift
func testMergeRequestsFailsWhenCreatedScopeFails() async {
    let httpClient = StubGitLabHTTPClient(responses: [
        "/api/v4/merge_requests?scope=assigned_to_me": StubHTTPResponse(
            statusCode: 200,
            body: #"[
              {"id":1001,"iid":41,"title":"Assigned","references":{"full":"ops/opshub!41"}}
            ]"#
        ),
        "/api/v4/merge_requests?scope=created_by_me": StubHTTPResponse(
            statusCode: 503,
            body: #"{"message":"Service unavailable"}"#
        )
    ])
    let service = GitLabService(
        settingsStore: StaticGitLabSettingsStore(),
        httpClient: httpClient
    )

    do {
        _ = try await service.mergeRequests()
        XCTFail("Expected created_by_me failure to fail the combined load")
    } catch {
        XCTAssertEqual(error as? GitLabServiceError, .requestFailed(503))
    }
}
```

- [ ] **Step 3: Chạy test để xác nhận baseline thất bại**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: test union chỉ thấy `assigned_to_me`; test lỗi không phát sinh request `created_by_me`.

- [ ] **Step 4: Implement tải song song, union và sort ổn định**

Thay implementation của `mergeRequests()`:

```swift
func mergeRequests() async throws -> [GitLabMergeRequest] {
    async let assignedItems = mergeRequests(scope: "assigned_to_me")
    async let createdItems = mergeRequests(scope: "created_by_me")
    let (assigned, created) = try await (assignedItems, createdItems)

    let unique = Dictionary(
        (assigned + created).map { ($0.id, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    return unique.values.sorted { lhs, rhs in
        if lhs.updatedAt != rhs.updatedAt {
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        return lhs.id < rhs.id
    }
}
```

Không bắt lỗi riêng từng scope; `try await` phải propagate lỗi để ViewModel dùng cơ chế partial-load hiện có.

- [ ] **Step 5: Chạy service tests và xác nhận Reviews không đổi**

Run:

```bash
swift test --filter GitLabServiceTests
```

Expected: tất cả `GitLabServiceTests` pass, bao gồm test `scope=reviews_for_me`.

### Task 2: Hiển thị rõ người request merge

**Files:**

- Modify: `Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift`

**Interfaces:**

- Produces: `GitLabWorkItemParticipant.role: String?`.
- Produces: `GitLabWorkItemParticipant.displayName: String`.
- Consumes: `GitLabMergeRequest.authorName` và `GitLabMergeRequest.authorAvatarURL`.

- [ ] **Step 1: Viết regression tests cho Merge Request, Review và author rỗng**

Trong `GitLabWorkItemPresentationTests`, mở rộng test MR hiện có và thêm hai test:

```swift
XCTAssertEqual(item.participants.first?.role, "Requested by")
XCTAssertEqual(item.participants.first?.displayName, "Requested by Octo Cat")
XCTAssertTrue(item.accessibilitySummary.contains("Requested by Octo Cat"))
```

```swift
func testReviewPresentationLabelsAuthorAsRequester() {
    let mergeRequest = GitLabMergeRequest(
        id: 1_042,
        iid: 42,
        title: "Review dashboard",
        project: "ops/opshub",
        status: .reviewing,
        authorName: "Review Author",
        updatedTime: "Now",
        webURL: nil
    )

    let item = GitLabWorkItemPresentation(mergeRequest: mergeRequest, context: .review)

    XCTAssertEqual(item.participants.first?.displayName, "Requested by Review Author")
}
```

```swift
func testMergeRequestPresentationOmitsBlankAuthor() {
    let mergeRequest = GitLabMergeRequest(
        id: 1_043,
        title: "Missing author",
        project: "ops/opshub",
        status: .opened,
        authorName: "   ",
        updatedTime: "Now",
        webURL: nil
    )

    let item = GitLabWorkItemPresentation(mergeRequest: mergeRequest, context: .mergeRequest)

    XCTAssertTrue(item.participants.isEmpty)
}
```

- [ ] **Step 2: Chạy presentation tests để xác nhận baseline thất bại**

Run:

```bash
swift test --filter GitLabWorkItemPresentationTests
```

Expected: compile fail vì `role` và `displayName` chưa tồn tại; blank author hiện vẫn tạo participant.

- [ ] **Step 3: Mở rộng participant metadata và MR mapping**

Trong `GitLabWorkItemPresentation.swift`, thay participant bằng:

```swift
struct GitLabWorkItemParticipant: Hashable, Sendable {
    let name: String
    let avatarURL: URL?
    let role: String?

    init(name: String, avatarURL: URL?, role: String? = nil) {
        self.name = name
        self.avatarURL = avatarURL
        self.role = role
    }

    var displayName: String {
        [role, name].compactMap { $0 }.joined(separator: " ")
    }
}
```

Đổi helper thành:

```swift
private static func participants(
    name: String?,
    avatarURL: URL?,
    role: String? = nil
) -> [GitLabWorkItemParticipant] {
    guard let name else { return [] }
    let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalizedName.isEmpty == false else { return [] }
    return [
        GitLabWorkItemParticipant(
            name: normalizedName,
            avatarURL: avatarURL,
            role: role
        )
    ]
}
```

MR mapping truyền role:

```swift
participants = Self.participants(
    name: mergeRequest.authorName,
    avatarURL: mergeRequest.authorAvatarURL,
    role: "Requested by"
)
```

Accessibility summary dùng `participants.map(\.displayName)` thay cho chỉ `name`. Issue, Pipeline và Notification không truyền `role`, nên giữ nguyên copy hiện tại.

- [ ] **Step 4: Render role và tên cạnh avatar**

Trong `GitLabWorkItemRow.participantAndTime`, thêm text khi có đúng một participant có role:

```swift
if item.participants.isEmpty == false {
    GitLabAvatarGroup(participants: item.participants)

    if item.participants.count == 1,
       let participant = item.participants.first,
       participant.role != nil {
        Text(participant.displayName)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }
}
```

Giữ timestamp và responsive layout hiện có.

- [ ] **Step 5: Chạy presentation tests và build**

Run:

```bash
swift test --filter GitLabWorkItemPresentationTests
swift build
```

Expected: tests pass và SwiftUI row compile thành công.

### Task 3: Xác minh toàn bộ thay đổi

**Files:**

- Verify only: toàn bộ working tree.

**Interfaces:**

- Consumes: kết quả của Task 1 và Task 2.
- Produces: bằng chứng test/build/diff sạch để bàn giao.

- [ ] **Step 1: Chạy toàn bộ unit tests**

Run:

```bash
swift test
```

Expected: toàn bộ test pass.

- [ ] **Step 2: Chạy debug và release build**

Run:

```bash
swift build
swift build -c release
```

Expected: cả hai build pass, không có strict-concurrency error từ hai `async let`.

- [ ] **Step 3: Kiểm tra diff và phạm vi file**

Run:

```bash
git diff --check
git status --short
git diff -- Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift \
  Sources/OpsHub/Features/GitLab/Models/GitLabWorkItemPresentation.swift \
  Sources/OpsHub/Features/GitLab/Components/GitLabWorkItemRow.swift \
  Tests/OpsHubTests/GitLabServiceTests.swift \
  Tests/OpsHubTests/GitLabWorkItemPresentationTests.swift
```

Expected: không có whitespace error; chỉ source, test và tài liệu đã chốt nằm trong diff.
