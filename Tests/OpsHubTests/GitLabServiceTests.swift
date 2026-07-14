import Foundation
import XCTest
@testable import OpsHub

final class GitLabServiceTests: XCTestCase {
    func testProjectsLoadsEveryMembershipProjectPageAndMapsFallbackName() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":7,"name":"opshub","name_with_namespace":"ops/opshub"}]"#,
                headers: ["X-Next-Page": "2"]
            ),
            "/api/v4/projects?page=2": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":8,"name":"worker"}]"#
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let projects = try await service.projects()

        XCTAssertEqual(projects.map(\.id), [7, 8])
        XCTAssertEqual(projects.map(\.nameWithNamespace), ["ops/opshub", "worker"])
        XCTAssertEqual(httpClient.requests.count, 2)
    }

    func testScopedMergeRequestsFiltersLoadedItemsByProject() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/merge_requests": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {"id":1001,"iid":41,"title":"OpsHub","references":{"full":"ops/opshub!41"}},
                  {"id":1002,"iid":42,"title":"Worker","references":{"full":"ops/worker!42"}}
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )
        let scope = GitLabProjectScope.project(
            GitLabProjectSummary(id: 7, nameWithNamespace: "ops/opshub", webURL: nil)
        )

        let mergeRequests = try await service.mergeRequests(scope: scope)

        XCTAssertEqual(mergeRequests.map(\.id), [41])
    }

    func testProjectsAndPipelinesReuseTheMembershipProjectCatalog() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":7,"name":"opshub","name_with_namespace":"ops/opshub"}]"#
            ),
            "/api/v4/projects/7/pipelines": StubHTTPResponse(statusCode: 200, body: "[]")
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        _ = try await service.projects()
        _ = try await service.pipelines()

        XCTAssertEqual(
            httpClient.requests.filter { $0.url?.path == "/api/v4/projects" }.count,
            1
        )
    }

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
                    "author": {
                      "id": 9,
                      "username": "octocat",
                      "name": "Octo Cat",
                      "avatar_url": "https://gitlab.example.com/uploads/avatar.png"
                    },
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
        XCTAssertEqual(mergeRequests.first?.authorName, "Octo Cat")
        XCTAssertEqual(mergeRequests.first?.authorAvatarURL?.absoluteString, "https://gitlab.example.com/uploads/avatar.png")
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

    func testMergeReviewsLoadsOpenItemsAssignedToCurrentUserForReview() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/merge_requests?scope=reviews_for_me": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 1002,
                    "iid": 43,
                    "project_id": 7,
                    "title": "Review GitLab dashboard changes",
                    "state": "opened",
                    "draft": false,
                    "labels": [],
                    "author": {
                      "id": 10,
                      "username": "review-author",
                      "name": "Review Author"
                    },
                    "reviewers": [
                      {
                        "id": 9,
                        "username": "current-user",
                        "name": "Current User"
                      }
                    ],
                    "references": {"full": "ops/opshub!43"},
                    "web_url": "https://gitlab.example.com/ops/opshub/-/merge_requests/43",
                    "updated_at": "2026-07-14T02:00:00.000Z"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let mergeReviews = try await service.mergeReviews()

        XCTAssertEqual(mergeReviews.map(\.id), [43])
        XCTAssertEqual(mergeReviews.first?.title, "Review GitLab dashboard changes")
        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v4/merge_requests")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "scope" })?
                .value,
            "reviews_for_me"
        )
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "state" })?
                .value,
            "opened"
        )
    }

    func testIssuesLoadsAllOpenItemsAndMarksAssignedItemsFromGitLabAPI() async throws {
        let now = ISO8601DateFormatter().date(from: "2026-07-13T12:00:00Z")!
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 2002,
                    "iid": 77,
                    "project_id": 7,
                    "title": "Make dashboard rows open GitLab",
                    "state": "opened",
                    "labels": [
                      {
                        "name": "priority::high",
                        "color": "#D9534F",
                        "text_color": "#FFFFFF"
                      }
                    ],
                    "assignees": [
                      {
                        "id": 19,
                        "username": "assignee",
                        "name": "Issue Assignee",
                        "avatar_url": "https://gitlab.example.com/uploads/assignee.png"
                      }
                    ],
                    "references": {"full": "ops/opshub#77"},
                    "web_url": "https://gitlab.example.com/ops/opshub/-/issues/77",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  },
                  {
                    "id": 2003,
                    "iid": 78,
                    "project_id": 7,
                    "title": "Production issue not assigned to me",
                    "state": "opened",
                    "labels": ["Bug Production"],
                    "references": {"full": "ops/opshub#78"}
                  }
                ]
                """
            ),
            "/api/v4/issues?scope=assigned_to_me": StubHTTPResponse(
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
                    "references": {"full": "ops/opshub#77"}
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient,
            now: { now }
        )

        let issues = try await service.issues()

        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues.first?.id, 77)
        XCTAssertEqual(issues.first?.title, "Make dashboard rows open GitLab")
        XCTAssertEqual(issues.first?.project, "ops/opshub")
        XCTAssertEqual(issues.first?.priority, .high)
        XCTAssertEqual(issues.first?.labels, ["priority::high"])
        XCTAssertEqual(
            issues.first?.labelDetails,
            [GitLabLabel(name: "priority::high", color: "#D9534F", textColor: "#FFFFFF")]
        )
        XCTAssertEqual(issues.first?.isAssignedToMe, true)
        XCTAssertEqual(issues.first?.isWorkflowProject, true)
        XCTAssertEqual(issues.first?.assigneeName, "Issue Assignee")
        XCTAssertEqual(
            issues.first?.assigneeAvatarURL?.absoluteString,
            "https://gitlab.example.com/uploads/assignee.png"
        )
        XCTAssertEqual(issues.last?.isAssignedToMe, false)
        XCTAssertEqual(issues.last?.isWorkflowProject, true)
        XCTAssertEqual(issues.first?.webURL?.absoluteString, "https://gitlab.example.com/ops/opshub/-/issues/77")
        XCTAssertTrue(httpClient.requests.contains(where: { request in
            guard let url = request.url else { return false }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath
                == "/api/v4/projects/social%2Fsocom-issues/issues"
        }))
        XCTAssertTrue(httpClient.requests.contains(where: { request in
            guard let url = request.url else { return false }
            return url.path == "/api/v4/issues"
                && URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .contains(URLQueryItem(name: "scope", value: "assigned_to_me")) == true
        }))
        let updatedAfterValues: [String] = httpClient.requests.compactMap { request -> String? in
            guard let url = request.url else { return nil }
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "updated_after" })?
                .value
        }
        XCTAssertEqual(updatedAfterValues, ["2026-06-13T12:00:00.000Z", "2026-06-13T12:00:00.000Z"])
        XCTAssertTrue(httpClient.requests.allSatisfy { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(URLQueryItem(name: "with_labels_details", value: "true")) == true
        })
    }

    func testIssuesLoadsEveryWorkflowProjectPage() async throws {
        let pageOneIssue = #"[{"id":3001,"iid":1,"title":"First page","labels":["Testing"]}]"#
        let pageTwoIssue = #"[{"id":3002,"iid":2,"title":"Second page","labels":["ToTest"]}]"#
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": StubHTTPResponse(
                statusCode: 200,
                body: pageOneIssue,
                headers: ["X-Next-Page": "2"]
            ),
            "/api/v4/projects/social%2Fsocom-issues/issues?page=2": StubHTTPResponse(
                statusCode: 200,
                body: pageTwoIssue
            ),
            "/api/v4/issues?scope=assigned_to_me": StubHTTPResponse(statusCode: 200, body: "[]")
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.issues()

        XCTAssertEqual(issues.map(\.id), [1, 2])
        XCTAssertTrue(issues.allSatisfy(\.isWorkflowProject))
    }

    func testNotificationsMapAuthorTimestampAndTargetURL() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/todos": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 303,
                    "action_name": "review requested",
                    "target_type": "MergeRequest",
                    "target_url": "https://gitlab.example.com/ops/opshub/-/merge_requests/42",
                    "created_at": "2026-06-25T02:00:00.000Z",
                    "author": {"id":9,"name":"Reviewer"},
                    "project": {"id":7,"name":"opshub","name_with_namespace":"ops/opshub"},
                    "target": {"id":42,"title":"Review dashboard"}
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let notifications = try await service.notifications()

        XCTAssertEqual(notifications.first?.authorName, "Reviewer")
        XCTAssertNotNil(notifications.first?.updatedAt)
        XCTAssertEqual(
            notifications.first?.webURL?.absoluteString,
            "https://gitlab.example.com/ops/opshub/-/merge_requests/42"
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
                    "web_url": "https://gitlab.example.com/ops/opshub/-/pipelines/9001",
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
        XCTAssertNotNil(pipelines.first?.updatedAt)
        XCTAssertEqual(
            pipelines.first?.webURL?.absoluteString,
            "https://gitlab.example.com/ops/opshub/-/pipelines/9001"
        )
        XCTAssertEqual(httpClient.requests.map { $0.url?.path }, [
            "/api/v4/projects",
            "/api/v4/projects/7/pipelines"
        ])
    }

    func testPipelineBatchKeepsSuccessfulProjectsAndReportsPartialFailures() async throws {
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

        let batch = try await service.pipelineBatch(scope: .allProjects)

        XCTAssertEqual(batch.pipelines.map(\.id), [9002])
        XCTAssertEqual(batch.pipelines.first?.project, "ops/private-service")
        XCTAssertEqual(batch.failedProjects, ["ops/opshub"])
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

        let path = request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?.percentEncodedPath
        } ?? ""
        let queryItems = URLComponents(
            url: request.url ?? URL(string: "https://gitlab.example.com")!,
            resolvingAgainstBaseURL: false
        )?.queryItems
        let scope = queryItems?
            .first(where: { $0.name == "scope" })?
            .value
        let page = queryItems?
            .first(where: { $0.name == "page" })?
            .value
        let candidateKeys = [
            page.map { "\(path)?page=\($0)" },
            scope.map { "\(path)?scope=\($0)" },
            path
        ]
        guard let response = candidateKeys.compactMap({ $0 }).compactMap({ responses[$0] }).first else {
            throw URLError(.badURL)
        }

        let url = request.url ?? URL(string: "https://gitlab.example.com")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"].merging(response.headers) { _, responseValue in
                responseValue
            }
        )!
        return (Data(response.body.utf8), httpResponse)
    }
}

private struct StubHTTPResponse {
    let statusCode: Int
    let body: String
    var headers: [String: String] = [:]
}
