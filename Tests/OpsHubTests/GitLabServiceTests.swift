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

        XCTAssertEqual(mergeRequests.map(\.id), [1001])
        XCTAssertEqual(mergeRequests.map(\.iid), [41])
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

    func testInvalidatingProjectCatalogCausesNextLoadToRefreshMembershipProjects() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":7,"name":"opshub","name_with_namespace":"ops/opshub"}]"#
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        _ = try await service.projects()
        await service.invalidateProjectCatalog()
        _ = try await service.projects()

        XCTAssertEqual(
            httpClient.requests.filter { $0.url?.path == "/api/v4/projects" }.count,
            2
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
                    ],
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
        XCTAssertEqual(mergeRequests.first?.id, 1001)
        XCTAssertEqual(mergeRequests.first?.iid, 42)
        XCTAssertEqual(mergeRequests.first?.title, "Wire GitLab REST service")
        XCTAssertEqual(mergeRequests.first?.project, "ops/opshub")
        XCTAssertEqual(mergeRequests.first?.status, .reviewing)
        XCTAssertEqual(mergeRequests.first?.authorName, "Octo Cat")
        XCTAssertEqual(mergeRequests.first?.authorAvatarURL?.absoluteString, "https://gitlab.example.com/uploads/avatar.png")
        XCTAssertEqual(mergeRequests.first?.assigneeName, "First Assignee")
        XCTAssertEqual(
            mergeRequests.first?.assigneeAvatarURL?.absoluteString,
            "https://gitlab.example.com/uploads/first-assignee.png"
        )
        XCTAssertEqual(mergeRequests.first?.webURL?.absoluteString, "https://gitlab.example.com/ops/opshub/-/merge_requests/42")
        let request = try XCTUnwrap(httpClient.requests.first { request in
            URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                .queryItems?
                .contains(URLQueryItem(name: "scope", value: "assigned_to_me")) == true
        })
        XCTAssertEqual(request.url?.path, "/api/v4/merge_requests")
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "scope" })?
                .value,
            "assigned_to_me"
        )
    }

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

    func testMergeRequestsFailsWhenCreatedScopeFails() async {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/merge_requests?scope=assigned_to_me": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {"id":1001,"iid":41,"title":"Assigned","references":{"full":"ops/opshub!41"}}
                ]
                """
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

        XCTAssertEqual(mergeReviews.map(\.id), [1002])
        XCTAssertEqual(mergeReviews.map(\.iid), [43])
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
        XCTAssertEqual(issues.first?.id, 2002)
        XCTAssertEqual(issues.first?.iid, 77)
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

        XCTAssertEqual(issues.map(\.id), [3001, 3002])
        XCTAssertEqual(issues.map(\.iid), [1, 2])
        XCTAssertTrue(issues.allSatisfy(\.isWorkflowProject))
    }

    func testSprintMilestonesLoadsEveryPageAndSkipsIncompleteItems() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/milestones": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 31,
                    "title": "Sprint 2026-W31",
                    "state": "active",
                    "start_date": "2026-07-29",
                    "due_date": "2026-08-04",
                    "web_url": "https://gitlab.example.com/social/socom-issues/-/milestones/31"
                  },
                  {
                    "id": 30,
                    "title": "Missing due date",
                    "start_date": "2026-07-22"
                  }
                ]
                """,
                headers: ["X-Next-Page": "2"]
            ),
            "/api/v4/projects/social%2Fsocom-issues/milestones?page=2": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 29,
                    "title": "Sprint 2026-W29",
                    "state": "closed",
                    "start_date": "2026-07-15",
                    "due_date": "2026-07-21"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let milestones = try await service.sprintMilestones(
            projectPath: GitLabWorkflowProject.path
        )

        XCTAssertEqual(milestones.map(\.id), [31, 29])
        XCTAssertEqual(milestones.map(\.title), ["Sprint 2026-W31", "Sprint 2026-W29"])
        XCTAssertEqual(
            milestones.first?.webURL,
            URL(string: "https://gitlab.example.com/social/socom-issues/-/milestones/31")
        )
        XCTAssertNil(milestones.last?.webURL)
        XCTAssertEqual(httpClient.requests.count, 2)
        let request = try XCTUnwrap(httpClient.requests.first)
        XCTAssertEqual(
            URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?
                .percentEncodedPath,
            "/api/v4/projects/social%2Fsocom-issues/milestones"
        )
        let query = Dictionary(
            uniqueKeysWithValues: (URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )?.queryItems ?? []).map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["order_by"], "due_date")
        XCTAssertEqual(query["sort"], "desc")
        XCTAssertEqual(query["per_page"], "100")
    }

    func testSprintIssuesUsesMilestoneContractPaginationAndMapsCurrentAssignee() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 4001,
                    "iid": 81,
                    "project_id": 7,
                    "title": "Sprint ticket",
                    "labels": ["Passed", "ToProduction", "Merged"],
                    "assignees": [
                      {
                        "id": 19,
                        "username": "alice",
                        "name": "Alice",
                        "avatar_url": "https://gitlab.example.com/alice.png"
                      }
                    ],
                    "references": {"full": "social/socom-issues#81"},
                    "created_at": "2026-07-29T02:00:00.000Z",
                    "updated_at": "2026-07-30T02:00:00.000Z",
                    "web_url": "https://gitlab.example.com/social/socom-issues/-/issues/81"
                  }
                ]
                """,
                headers: ["X-Next-Page": "2"]
            ),
            "/api/v4/projects/social%2Fsocom-issues/issues?page=2": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":4002,"iid":82,"title":"Second page","labels":[]}]"#
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.sprintIssues(
            projectPath: GitLabWorkflowProject.path,
            milestoneTitle: "Sprint 2026-W31"
        )

        XCTAssertEqual(issues.map(\.id), [4001, 4002])
        XCTAssertEqual(issues.first?.assignee?.id, 19)
        XCTAssertEqual(issues.first?.assignee?.name, "Alice")
        XCTAssertEqual(issues.first?.project, "social/socom-issues")
        XCTAssertNotNil(issues.first?.createdAt)
        XCTAssertNotNil(issues.first?.updatedAt)
        let request = try XCTUnwrap(httpClient.requests.first)
        let queryItems = URLComponents(
            url: try XCTUnwrap(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let query = Dictionary(
            uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["state"], "all")
        XCTAssertEqual(query["milestone"], "Sprint 2026-W31")
        XCTAssertEqual(query["with_labels_details"], "true")
        XCTAssertEqual(query["per_page"], "100")
        XCTAssertNil(query["scope"])
        XCTAssertNil(query["updated_after"])
    }

    func testProductionBugsUsesDateLabelContractWithoutMilestoneOrAssigneeScope() async throws {
        let after = ISO8601DateFormatter().date(from: "2026-07-28T17:00:00Z")!
        let before = ISO8601DateFormatter().date(from: "2026-08-04T17:00:00Z")!
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/social%2Fsocom-issues/issues": StubHTTPResponse(
                statusCode: 200,
                body: #"[{"id":5001,"iid":91,"title":"Production bug","labels":["Bug Production"],"created_at":"2026-07-30T02:00:00.000Z"}]"#
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let issues = try await service.productionBugs(
            projectPath: GitLabWorkflowProject.path,
            createdAfter: after,
            createdBefore: before
        )

        XCTAssertEqual(issues.map(\.id), [5001])
        let request = try XCTUnwrap(httpClient.requests.first)
        let queryItems = URLComponents(
            url: try XCTUnwrap(request.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []
        let query = Dictionary(
            uniqueKeysWithValues: queryItems.map { ($0.name, $0.value ?? "") }
        )
        XCTAssertEqual(query["state"], "all")
        XCTAssertEqual(query["labels"], "Bug Production")
        XCTAssertEqual(query["created_after"], "2026-07-28T17:00:00.000Z")
        XCTAssertEqual(query["created_before"], "2026-08-04T17:00:00.000Z")
        XCTAssertEqual(query["with_labels_details"], "true")
        XCTAssertEqual(query["per_page"], "100")
        XCTAssertNil(query["milestone"])
        XCTAssertNil(query["scope"])
        XCTAssertNil(query["updated_after"])
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
                    "name_with_namespace": "social/opshub"
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
                    "ref": "v2.4.0",
                    "source": "push",
                    "status": "failed",
                    "web_url": "https://gitlab.example.com/ops/opshub/-/pipelines/9001",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                  }
                ]
                """
            ),
            "/api/v4/projects/7/pipelines/9001": StubHTTPResponse(
                statusCode: 200,
                body: """
                {
                    "id": 9001,
                    "project_id": 7,
                    "ref": "v2.4.0",
                    "tag": true,
                    "source": "push",
                    "status": "failed",
                    "user": {
                      "id": 12,
                      "name": "Release Owner",
                      "username": "release-owner",
                      "avatar_url": "https://gitlab.example.com/avatar.png"
                    },
                    "web_url": "https://gitlab.example.com/ops/opshub/-/pipelines/9001",
                    "updated_at": "2026-06-25T02:00:00.000Z"
                }
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
        XCTAssertEqual(pipelines.first?.projectID, 7)
        XCTAssertEqual(pipelines.first?.project, "social/opshub")
        XCTAssertEqual(pipelines.first?.branch, "v2.4.0")
        XCTAssertTrue(pipelines.first?.isTag == true)
        XCTAssertEqual(pipelines.first?.source, "push")
        XCTAssertEqual(pipelines.first?.userName, "Release Owner")
        XCTAssertEqual(
            pipelines.first?.userAvatarURL?.absoluteString,
            "https://gitlab.example.com/avatar.png"
        )
        XCTAssertEqual(pipelines.first?.status, .failed)
        XCTAssertNotNil(pipelines.first?.updatedAt)
        XCTAssertEqual(
            pipelines.first?.webURL?.absoluteString,
            "https://gitlab.example.com/ops/opshub/-/pipelines/9001"
        )
        XCTAssertEqual(httpClient.requests.map { $0.url?.path }, [
            "/api/v4/projects",
            "/api/v4/projects/7/pipelines",
            "/api/v4/projects/7/pipelines/9001"
        ])
    }

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
                "/api/v4/projects/7/pipelines/7001",
                "/api/v4/projects/8/pipelines",
                "/api/v4/projects/8/pipelines/8001",
                "/api/v4/projects/9/pipelines",
                "/api/v4/projects/9/pipelines/9001"
            ]
        )
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
                    "name_with_namespace": "social/opshub"
                  },
                  {
                    "id": 8,
                    "name": "private-service",
                    "name_with_namespace": "Hara AI/private-service"
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
        XCTAssertEqual(batch.pipelines.first?.project, "Hara AI/private-service")
        XCTAssertEqual(batch.failedProjects, ["social/opshub"])
        XCTAssertEqual(
            httpClient.requests.compactMap { $0.url?.path }.sorted(),
            [
                "/api/v4/projects",
                "/api/v4/projects/7/pipelines",
                "/api/v4/projects/8/pipelines",
                "/api/v4/projects/8/pipelines/9002"
            ]
        )
    }

    func testPipelineJobsMapStageActionFieldsAndUsePaginationContract() async throws {
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/7/pipelines/9001/jobs": StubHTTPResponse(
                statusCode: 200,
                body: """
                [
                  {
                    "id": 301,
                    "name": "deploy-production",
                    "stage": "deploy",
                    "status": "manual",
                    "allow_failure": false,
                    "archived": false,
                    "tag": false,
                    "web_url": "https://gitlab.example.com/social/opshub/-/jobs/301"
                  }
                ]
                """
            )
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        let jobs = try await service.pipelineJobs(projectID: 7, pipelineID: 9001)

        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs.first?.stage, "deploy")
        XCTAssertEqual(jobs.first?.status, .manual)
        XCTAssertFalse(jobs.first?.isArchived == true)
        let queryItems = URLComponents(
            url: try XCTUnwrap(httpClient.requests.first?.url),
            resolvingAgainstBaseURL: false
        )?.queryItems
        XCTAssertEqual(queryItems?.first(where: { $0.name == "include_retried" })?.value, "false")
        XCTAssertEqual(queryItems?.first(where: { $0.name == "per_page" })?.value, "100")
    }

    func testJobActionsUsePostAndReturnUpdatedJob() async throws {
        let response = StubHTTPResponse(
            statusCode: 200,
            body: """
            {
              "id": 301,
              "name": "deploy-production",
              "stage": "deploy",
              "status": "pending",
              "archived": false
            }
            """
        )
        let httpClient = StubGitLabHTTPClient(responses: [
            "/api/v4/projects/7/jobs/301/play": response,
            "/api/v4/projects/7/jobs/301/retry": response,
            "/api/v4/projects/7/jobs/301/cancel": response
        ])
        let service = GitLabService(
            settingsStore: StaticGitLabSettingsStore(),
            httpClient: httpClient
        )

        _ = try await service.playJob(projectID: 7, jobID: 301)
        _ = try await service.retryJob(projectID: 7, jobID: 301)
        _ = try await service.cancelJob(projectID: 7, jobID: 301)

        XCTAssertEqual(httpClient.requests.map(\.httpMethod), ["POST", "POST", "POST"])
        XCTAssertEqual(
            httpClient.requests.compactMap { $0.url?.path },
            [
                "/api/v4/projects/7/jobs/301/play",
                "/api/v4/projects/7/jobs/301/retry",
                "/api/v4/projects/7/jobs/301/cancel"
            ]
        )
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
