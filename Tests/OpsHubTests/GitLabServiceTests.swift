import Foundation
import XCTest
@testable import OpsHub

final class GitLabServiceTests: XCTestCase {
    func testConnectionCallsGitLabUserEndpointWithPrivateToken() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/user": StubHTTPResponse(statusCode: 200, body: #"{"id":1}"#)
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let result = try await service.testConnection(
            settings: GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret"
            )
        )

        XCTAssertEqual(result, .connected)
        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v4/user")
        XCTAssertEqual(request.value(forHTTPHeaderField: "PRIVATE-TOKEN"), "glpat-secret")
    }

    func testMergeRequestsLoadsAssignedOpenItemsFromGitLabAPI() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/merge_requests": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 1001,
                    "iid": 42,
                    "project_id": 7,
                    "title": "Wire GitLab REST service",
                    "state": "opened",
                    "draft": false,
                    "labels": ["review"],
                    "reviewers": [],
                    "references": {"full": "ops/opshub!42"},
                    "web_url": "https://gitlab.example.com/ops/opshub/-/merge_requests/42",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let mergeRequests = try await service.mergeRequests()

        XCTAssertEqual(mergeRequests.count, 1)
        XCTAssertEqual(mergeRequests.first?.id, 42)
        XCTAssertEqual(mergeRequests.first?.title, "Wire GitLab REST service")
        XCTAssertEqual(mergeRequests.first?.project, "ops/opshub")
        XCTAssertEqual(mergeRequests.first?.status, .reviewing)
        XCTAssertEqual(mergeRequests.first?.webURL?.absoluteString, "https://gitlab.example.com/ops/opshub/-/merge_requests/42")
        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v4/merge_requests")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "scope" })?
                .value,
            "assigned_to_me"
        )
    }

    func testIssuesLoadsAssignedOpenItemsFromGitLabAPI() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/issues": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 2002,
                    "iid": 77,
                    "project_id": 7,
                    "title": "Make dashboard rows open GitLab",
                    "state": "opened",
                    "labels": ["priority::high"],
                    "references": {"full": "ops/opshub#77"},
                    "web_url": "https://gitlab.example.com/ops/opshub/-/issues/77",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.issues()

        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.id, 77)
        XCTAssertEqual(issues.first?.title, "Make dashboard rows open GitLab")
        XCTAssertEqual(issues.first?.project, "ops/opshub")
        XCTAssertEqual(issues.first?.priority, .high)
        XCTAssertEqual(issues.first?.webURL?.absoluteString, "https://gitlab.example.com/ops/opshub/-/issues/77")
        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v4/issues")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "scope" })?
                .value,
            "assigned_to_me"
        )
    }

    func testPipelinesLoadFromRecentMembershipProjects() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 7,
                    "name": "opshub",
                    "name_with_namespace": "ops/opshub"
                  }
                ]
                """
            ),
            "/api/v4/projects/7/pipelines": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 9001,
                    "project_id": 7,
                    "ref": "main",
                    "status": "failed",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let pipelines = try await service.pipelines()

        XCTAssertEqual(pipelines.count, 1)
        XCTAssertEqual(pipelines.first?.id, 9001)
        XCTAssertEqual(pipelines.first?.project, "ops/opshub")
        XCTAssertEqual(pipelines.first?.branch, "main")
        XCTAssertEqual(pipelines.first?.status, .failed)
        XCTAssertEqual(httpClient.requests.map { $0.url?.path }, [
            "/api/v4/projects",
            "/api/v4/projects/7/pipelines"
        ])
    }

    func testPipelinesSkipsProjectsThatCannotLoadPipelines() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 7,
                    "name": "opshub",
                    "name_with_namespace": "ops/opshub"
                  },
                  {
                    "id": 8,
                    "name": "private-service",
                    "name_with_namespace": "ops/private-service"
                  }
                ]
                """
            ),
            "/api/v4/projects/7/pipelines": StubHTTPResponse(
                statusCode: 403,
                body: #"{"message":"403 Forbidden"}"#
            ),
            "/api/v4/projects/8/pipelines": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 9002,
                    "project_id": 8,
                    "ref": "main",
                    "status": "success",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let pipelines = try await service.pipelines()

        XCTAssertEqual(pipelines.map(\.id), [9002])
        XCTAssertEqual(pipelines.first?.project, "ops/private-service")
        XCTAssertEqual(httpClient.requests.map { $0.url?.path }, [
            "/api/v4/projects",
            "/api/v4/projects/7/pipelines",
            "/api/v4/projects/8/pipelines"
        ])
    }
}

private struct StaticGitLabSettingsStore: GitLabSettingsStoring {
    func load() -> GitLabSettings {
        GitLabSettings(
            gitLabURL: "https://gitlab.example.com",
            personalAccessToken: "glpat-secret"
        )
    }

    func save(_ settings: GitLabSettings) throws {}
}

private final class StubGitLabHTTPClient: GitLabHTTPClient, @unchecked Sendable {
    private let responses: [String: StubHTTPResponse]
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    init(responses: [String: StubHTTPResponse]) {
        self.responses = responses
    }

    var requests: [URLRequest] {
        lock.withLock {
            recordedRequests
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock {
            recordedRequests.append(request)
        }

        let path = request.url?.path ?? ""
        guard let response = responses[path] else {
            throw URLError(.badURL)
        }

        let url = request.url ?? URL(string: "https://gitlab.example.com")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(response.body.utf8), httpResponse)
    }
}

private struct StubHTTPResponse {
    let statusCode: Int
    let body: String
}
