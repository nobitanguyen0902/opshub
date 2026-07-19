### Task 1: Project member API and pagination

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Models/DevRoomMember.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Services/DevRoomMemberServices.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Tests/OpsHubTests/DevRoomServiceTests.swift`

**Interfaces:**
- Consumes: `GitLabWorkflowProject.path`, `GitLabService.makeRequest(settings:path:queryItems:)`, `sendAllPages(_:)`.
- Produces: `DevRoomMemberServicing.projectMembers(projectPath:) async throws -> [DevRoomProjectMember]` cho Settings Task 3.

- [ ] **Step 1: Viết failing test cho members/all và pagination**

Thêm vào `DevRoomServiceTests`:

```swift
func testProjectMembersLoadsAllPagesAndMapsIdentity() async throws {
    let httpClient = DevRoomStubGitLabHTTPClient(responses: [
        "/api/v4/projects/social%2Fsocom-issues/members/all": DevRoomStubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":19,"username":"alice","name":"Alice","avatar_url":"https://gitlab.example.com/alice.png","access_level":30}]"#,
            headers: ["X-Next-Page": "2"]
        ),
        "/api/v4/projects/social%2Fsocom-issues/members/all?page=2": DevRoomStubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":20,"username":"bob","name":"Bob","avatar_url":null,"access_level":40}]"#
        )
    ])
    let service = GitLabService(
        settingsStore: DevRoomStaticGitLabSettingsStore(),
        httpClient: httpClient
    )

    let members = try await service.projectMembers(projectPath: GitLabWorkflowProject.path)

    XCTAssertEqual(members.map(\.id), [19, 20])
    XCTAssertEqual(members.map(\.username), ["alice", "bob"])
    XCTAssertEqual(members.map(\.accessLevel), [30, 40])
    XCTAssertEqual(httpClient.requests.count, 2)
    let first = try XCTUnwrap(httpClient.requests.first?.url)
    let components = try XCTUnwrap(URLComponents(url: first, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.percentEncodedPath, "/api/v4/projects/social%2Fsocom-issues/members/all")
    XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "per_page", value: "100")) == true)
}
```

- [ ] **Step 2: Chạy test để xác nhận fail vì method chưa tồn tại**

```bash
swift test --filter DevRoomServiceTests/testProjectMembers
```

Expected: build fail với `value of type 'GitLabService' has no member 'projectMembers'`.

- [ ] **Step 3: Tạo member model và service protocol riêng**

```swift
import Foundation

struct DevRoomProjectMember: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
    let accessLevel: Int

    var accessLevelTitle: String {
        switch accessLevel {
        case 50...: "Owner"
        case 40..<50: "Maintainer"
        case 30..<40: "Developer"
        case 20..<30: "Reporter"
        case 10..<20: "Guest"
        default: "Minimal access"
        }
    }
}
```

```swift
protocol DevRoomMemberServicing: Sendable {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember]
}
```

- [ ] **Step 4: Implement DTO, request builder và mapping trong GitLabService**

DTO private dùng snake-case decode hiện có:

```swift
private struct GitLabProjectMember: Decodable {
    let id: Int
    let username: String
    let name: String
    let avatarUrl: URL?
    let accessLevel: Int

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarUrl = "avatar_url"
        case accessLevel = "access_level"
    }
}
```

Thêm helper tổng quát cho project subpath để issues và members cùng encode `/` thành `%2F`:

```swift
private func makeProjectRequest(
    settings: GitLabSettings,
    projectPath: String,
    suffix: String,
    queryItems: [URLQueryItem]
) throws -> URLRequest
```

`projectMembers` dùng suffix `members/all`, query `per_page=100`, `sendAllPages`, map model và sort theo `name.localizedCaseInsensitiveCompare`, tie-break theo ID.

- [ ] **Step 5: Chạy tests service liên quan**

```bash
swift test --filter DevRoomServiceTests
swift test --filter GitLabServiceTests
```

Expected: toàn bộ pass; request issue hiện có vẫn giữ nguyên path/query.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Models/DevRoomMember.swift Sources/OpsHub/Features/DevRoom/Services/DevRoomMemberServices.swift Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift Tests/OpsHubTests/DevRoomServiceTests.swift
git commit -m "feat(dev-room): load project members"
```

---

