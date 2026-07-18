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
