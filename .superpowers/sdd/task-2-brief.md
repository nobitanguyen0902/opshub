### Task 2: GitLab project issue service riêng cho Dev Room

**Files:**
- Create: Sources/OpsHub/Features/DevRoom/Services/DevRoomServices.swift
- Modify: Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift:101-213, 394-412
- Create: Tests/OpsHubTests/DevRoomServiceTests.swift

**Interfaces:**
- Consumes: GitLabWorkflowProject.path, DevRoomSourceIssue, DevRoomEmployee.
- Produces:
  - DevRoomServicing.openIssues(projectPath:) async throws -> [DevRoomSourceIssue]
  - GitLabService conformance to DevRoomServicing

- [ ] **Step 1: Viết failing service tests cho query, mapping và pagination**

Tạo Tests/OpsHubTests/DevRoomServiceTests.swift với test doubles file-local:

~~~swift
import Foundation
import XCTest
@testable import OpsHub

final class DevRoomServiceTests: XCTestCase {
    func testOpenIssuesUsesProjectOpenedQueryWithoutRecencyOrAssignedScope() async throws {
        let httpClient = DevRoomStubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": DevRoomStubHTTPResponse(
                statusCode: 200,
                body: """
                [{
                  "id": 10,
                  "iid": 7,
                  "title": "Move task to QC",
                  "state": "opened",
                  "labels": ["Doing"],
                  "assignees": [{
                    "id": 19,
                    "username": "alice",
                    "name": "Alice",
                    "avatar_url": "https://gitlab.example.com/alice.png"
                  }],
                  "updated_at": "2026-07-18T02:00:00.000Z",
                  "web_url": "https://gitlab.example.com/social/socom-issues/-/issues/7"
                }]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: DevRoomStaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.openIssues(projectPath: GitLabWorkflowProject.path)

        XCTAssertEqual(issues.map(\.id), [10])
        XCTAssertEqual(issues.first?.assignee?.id, 19)
        XCTAssertEqual(issues.first?.assignee?.name, "Alice")
        XCTAssertEqual(issues.first?.labels, ["Doing"])
        let request = try XCTUnwrap(httpClient.requests.first)
        let components = try XCTUnwrap(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)
        )
        XCTAssertEqual(components.percentEncodedPath, "/api/v4/projects/social%2Fsocom-issues/issues")
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "state", value: "opened")) == true)
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "with_labels_details", value: "true")) == true)
        XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "per_page", value: "100")) == true)
        XCTAssertFalse(components.queryItems?.contains(where: { $0.name == "updated_after" }) == true)
        XCTAssertFalse(components.queryItems?.contains(where: { $0.name == "scope" }) == true)
    }

    func testOpenIssuesLoadsEveryPageAndKeepsUnassignedForAggregatorFiltering() async throws {
        let httpClient = DevRoomStubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": DevRoomStubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":1,"iid":1,"title":"Assigned","labels":["Todo"],"assignees":[{"id":7,"name":"Alice"}]}]"#,
                headers: ["X-Next-Page": "2"]
            ),
            "/api/v4/projects/social%2Fsocom-issues/issues?page=2": DevRoomStubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":2,"iid":2,"title":"Unassigned","labels":["Doing"],"assignees":[]}]"#
            )
        ])
        let service = GitLabService(
            settingsStore: DevRoomStaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.openIssues(projectPath: GitLabWorkflowProject.path)

        XCTAssertEqual(issues.map(\.id), [1, 2])
        XCTAssertEqual(issues.first?.assignee?.id, 7)
        XCTAssertNil(issues.last?.assignee)
        XCTAssertEqual(httpClient.requests.count, 2)
    }
}

private struct DevRoomStaticGitLabSettingsStore: GitLabSettingsStoring {
    func load() -> GitLabSettings {
        GitLabSettings(
            gitLabURL: "https://gitlab.example.com",
            personalAccessToken: "glpat-secret"
        )
    }

    func save(_ settings: GitLabSettings) throws {}
}

private final class DevRoomStubGitLabHTTPClient: GitLabHTTPClient, @unchecked Sendable {
    private let responses: [String: DevRoomStubHTTPResponse]
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    init(responses: [String: DevRoomStubHTTPResponse]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.withLock { recordedRequests }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { recordedRequests.append(request) }
        let components = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)
        }
        let path = components?.percentEncodedPath ?? ""
        let page = components?.queryItems?.first(where: { $0.name == "page" })?.value
        let keys = [page.map { "\(path)?page=\($0)" }, path]
        guard let response = keys.compactMap({ $0 }).compactMap({ responses[$0] }).first else {
            throw URLError(.badURL)
        }
        let url = request.url ?? URL(string: "https://gitlab.example.com")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"].merging(response.headers) { _, new in new }
        )!
        return (Data(response.body.utf8), httpResponse)
    }
}

private struct DevRoomStubHTTPResponse {
    let statusCode: Int
    let body: String
    var headers: [String: String] = [:]
}
~~~

- [ ] **Step 2: Chạy service tests và xác nhận fail**

Run:

~~~bash
swift test --filter DevRoomServiceTests
~~~

Expected: build FAIL vì DevRoomServicing/openIssues chưa tồn tại.

- [ ] **Step 3: Thêm protocol và GitLabService implementation**

Tạo Sources/OpsHub/Features/DevRoom/Services/DevRoomServices.swift:

~~~swift
protocol DevRoomServicing: Sendable {
    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue]
}
~~~

Trong GitLabServices.swift:

1. Đổi declaration thành:

~~~swift
struct GitLabService: GitLabServicing, DevRoomServicing, @unchecked Sendable {
~~~

2. Thêm method:

~~~swift
func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
    let settings = try configuredSettings()
    let request = try makeProjectIssuesRequest(
        settings: settings,
        projectPath: projectPath,
        queryItems: [
            URLQueryItem(name: "state", value: "opened"),
            URLQueryItem(name: "order_by", value: "updated_at"),
            URLQueryItem(name: "sort", value: "desc"),
            URLQueryItem(name: "with_labels_details", value: "true"),
            URLQueryItem(name: "per_page", value: "100")
        ]
    )
    let issues: [GitLabRESTIssue] = try await sendAllPages(request)
    return issues.map { issue in
        let user = issue.assignees.first
        return DevRoomSourceIssue(
            id: issue.id,
            iid: issue.iid ?? issue.id,
            title: issue.title,
            labels: issue.labels.map(\.name),
            assignee: user.map {
                DevRoomEmployee(
                    id: $0.id,
                    name: $0.name ?? $0.username ?? "GitLab user #\($0.id)",
                    username: $0.username,
                    avatarURL: $0.avatarUrl
                )
            },
            updatedAt: date(from: issue.updatedAt),
            webURL: issue.webUrl
        )
    }
}
~~~

3. Thay helper hardcode bằng helper tổng quát và giữ wrapper cũ:

~~~swift
private func makeWorkflowProjectIssuesRequest(
    settings: GitLabSettings,
    queryItems: [URLQueryItem]
) throws -> URLRequest {
    try makeProjectIssuesRequest(
        settings: settings,
        projectPath: GitLabWorkflowProject.path,
        queryItems: queryItems
    )
}

private func makeProjectIssuesRequest(
    settings: GitLabSettings,
    projectPath: String,
    queryItems: [URLQueryItem]
) throws -> URLRequest {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    guard let encodedProject = projectPath.addingPercentEncoding(withAllowedCharacters: allowed) else {
        throw GitLabServiceError.invalidURL
    }

    var request = try makeRequest(settings: settings, path: "projects", queryItems: [])
    guard let requestURL = request.url,
          var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
        throw GitLabServiceError.invalidURL
    }
    components.percentEncodedPath += "/\(encodedProject)/issues"
    components.queryItems = queryItems
    guard let url = components.url else {
        throw GitLabServiceError.invalidURL
    }
    request.url = url
    return request
}
~~~

- [ ] **Step 4: Chạy Dev Room service tests và GitLab regression tests**

Run:

~~~bash
swift test --filter DevRoomServiceTests
swift test --filter GitLabServiceTests
~~~

Expected: cả hai test suites PASS; test GitLab cũ vẫn thấy /projects/social%2Fsocom-issues/issues và updated_after.

- [ ] **Step 5: Commit service**

~~~bash
git add Sources/OpsHub/Features/DevRoom/Services/DevRoomServices.swift Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift Tests/OpsHubTests/DevRoomServiceTests.swift
git commit -m "feat(dev-room): load open project issues"
~~~

---

