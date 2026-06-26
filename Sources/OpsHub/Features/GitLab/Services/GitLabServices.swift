import Foundation

/// Provides GitLab dashboard data and settings validation.
protocol GitLabServicing: Sendable {
    func dashboardStatistics() async throws -> [GitLabStatistic]
    func mergeRequests() async throws -> [GitLabMergeRequest]
    func issues() async throws -> [GitLabIssue]
    func notifications() async throws -> [GitLabNotification]
    func pipelines() async throws -> [GitLabPipeline]
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult
}

/// Minimal HTTP client abstraction used by the GitLab REST service and tests.
protocol GitLabHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GitLabHTTPClient {}

/// GitLab REST-backed dashboard data source.
struct GitLabService: GitLabServicing, @unchecked Sendable {
    private let settingsStore: any GitLabSettingsStoring
    private let httpClient: any GitLabHTTPClient
    private let decoder: JSONDecoder
    private let isoDateFormatter: ISO8601DateFormatter

    init(
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore(),
        httpClient: any GitLabHTTPClient = URLSession.shared
    ) {
        self.settingsStore = settingsStore
        self.httpClient = httpClient
        decoder = JSONDecoder()
        isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func dashboardStatistics() async throws -> [GitLabStatistic] {
        async let loadedMergeRequests = mergeRequests()
        async let loadedIssues = issues()
        async let loadedNotifications = notifications()
        async let loadedPipelines = pipelines()

        let mergeRequests = try await loadedMergeRequests
        let issues = try await loadedIssues
        let notifications = try await loadedNotifications
        let pipelines = try await loadedPipelines
        let failedPipelines = pipelines.filter { $0.status == .failed }.count
        let reviewRequests = notifications.filter { $0.kind == .reviewRequested }.count

        return [
            GitLabStatistic(
                icon: "arrow.triangle.merge",
                title: "Merge Requests",
                number: "\(mergeRequests.count)",
                subtitle: "Assigned open merge requests",
                webURL: nil
            ),
            GitLabStatistic(
                icon: "exclamationmark.circle",
                title: "Issues",
                number: "\(issues.count)",
                subtitle: "Assigned open issues",
                webURL: nil
            ),
            GitLabStatistic(
                icon: "bell.badge",
                title: "Notifications",
                number: "\(notifications.count)",
                subtitle: "\(reviewRequests) review requests",
                webURL: nil
            ),
            GitLabStatistic(
                icon: "play.circle",
                title: "Pipelines",
                number: "\(pipelines.count)",
                subtitle: "\(failedPipelines) failed pipelines",
                webURL: nil
            )
        ]
    }

    func mergeRequests() async throws -> [GitLabMergeRequest] {
        let settings = try configuredSettings()
        let request = try makeRequest(
            settings: settings,
            path: "merge_requests",
            queryItems: [
                URLQueryItem(name: "scope", value: "assigned_to_me"),
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: "20")
            ]
        )
        let response: [GitLabRESTMergeRequest] = try await send(request)
        return response.map(mapMergeRequest)
    }

    func issues() async throws -> [GitLabIssue] {
        let settings = try configuredSettings()
        let request = try makeRequest(
            settings: settings,
            path: "issues",
            queryItems: [
                URLQueryItem(name: "scope", value: "assigned_to_me"),
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: "20")
            ]
        )
        let response: [GitLabRESTIssue] = try await send(request)
        return response.map(mapIssue)
    }

    func notifications() async throws -> [GitLabNotification] {
        let settings = try configuredSettings()
        let request = try makeRequest(
            settings: settings,
            path: "todos",
            queryItems: [
                URLQueryItem(name: "state", value: "pending"),
                URLQueryItem(name: "per_page", value: "20")
            ]
        )
        let response: [GitLabRESTNotification] = try await send(request)
        return response.map(mapNotification)
    }

    func pipelines() async throws -> [GitLabPipeline] {
        let settings = try configuredSettings()
        let projectsRequest = try makeRequest(
            settings: settings,
            path: "projects",
            queryItems: [
                URLQueryItem(name: "membership", value: "true"),
                URLQueryItem(name: "simple", value: "true"),
                URLQueryItem(name: "order_by", value: "last_activity_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "per_page", value: "10")
            ]
        )
        let projects: [GitLabProject] = try await send(projectsRequest)
        var pipelines: [GitLabPipeline] = []

        for project in projects.prefix(5) {
            let request = try makeRequest(
                settings: settings,
                path: "projects/\(project.id)/pipelines",
                queryItems: [
                    URLQueryItem(name: "per_page", value: "5")
                ]
            )

            do {
                let response: [GitLabRESTPipeline] = try await send(request)
                pipelines.append(contentsOf: response.map { mapPipeline($0, project: project) })
            } catch {
                continue
            }
        }

        return Array(pipelines.sorted { $0.id > $1.id }.prefix(20))
    }

    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult {
        do {
            let request = try makeRequest(
                settings: settings,
                path: "user",
                queryItems: []
            )
            let (_, response) = try await httpClient.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitLabServiceError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                return .connected
            case 401, 403:
                return .unauthorized
            default:
                throw GitLabServiceError.requestFailed(httpResponse.statusCode)
            }
        } catch let error as GitLabServiceError {
            if case .unauthorized = error {
                return .unauthorized
            }
            throw error
        } catch let error as URLError where error.code == .timedOut {
            return .timeout
        }
    }

    private func configuredSettings() throws -> GitLabSettings {
        let settings = settingsStore.load()
        guard !settings.gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !settings.personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GitLabServiceError.missingSettings
        }

        return settings
    }

    private func makeRequest(
        settings: GitLabSettings,
        path: String,
        queryItems: [URLQueryItem]
    ) throws -> URLRequest {
        let trimmedURL = settings.gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = settings.personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            throw GitLabServiceError.missingSettings
        }

        guard let baseURL = URL(string: trimmedURL), baseURL.scheme != nil, baseURL.host != nil else {
            throw GitLabServiceError.invalidURL
        }

        let apiURL = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("v4")
            .appendingPathComponent(path)
        guard var components = URLComponents(url: apiURL, resolvingAgainstBaseURL: false) else {
            throw GitLabServiceError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw GitLabServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(trimmedToken, forHTTPHeaderField: "PRIVATE-TOKEN")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try decoder.decode(Response.self, from: data)
        case 401, 403:
            throw GitLabServiceError.unauthorized
        default:
            throw GitLabServiceError.requestFailed(httpResponse.statusCode)
        }
    }

    private func mapMergeRequest(_ mergeRequest: GitLabRESTMergeRequest) -> GitLabMergeRequest {
        GitLabMergeRequest(
            id: mergeRequest.iid ?? mergeRequest.id,
            title: mergeRequest.title,
            project: projectName(from: mergeRequest.references, projectId: mergeRequest.projectId),
            status: mergeRequestStatus(for: mergeRequest),
            updatedTime: relativeTime(from: mergeRequest.updatedAt),
            webURL: mergeRequest.webUrl
        )
    }

    private func mapIssue(_ issue: GitLabRESTIssue) -> GitLabIssue {
        GitLabIssue(
            id: issue.iid ?? issue.id,
            title: issue.title,
            project: projectName(from: issue.references, projectId: issue.projectId),
            priority: issuePriority(for: issue.labels),
            updatedTime: relativeTime(from: issue.updatedAt),
            webURL: issue.webUrl
        )
    }

    private func mapNotification(_ notification: GitLabRESTNotification) -> GitLabNotification {
        GitLabNotification(
            id: notification.id,
            title: notification.target?.title ?? notification.body ?? notification.actionName ?? "GitLab notification",
            project: notification.project?.nameWithNamespace ?? notification.project?.name ?? "GitLab",
            kind: notificationKind(for: notification),
            updatedTime: relativeTime(from: notification.createdAt)
        )
    }

    private func mapPipeline(_ pipeline: GitLabRESTPipeline, project: GitLabProject) -> GitLabPipeline {
        GitLabPipeline(
            id: pipeline.id,
            project: project.nameWithNamespace ?? project.name ?? "Project #\(project.id)",
            branch: pipeline.ref ?? "-",
            status: pipelineStatus(for: pipeline.status),
            updatedTime: relativeTime(from: pipeline.updatedAt ?? pipeline.createdAt)
        )
    }

    private func projectName(from references: GitLabReferences?, projectId: Int?) -> String {
        if let fullReference = references?.full {
            if let separatorIndex = fullReference.firstIndex(where: { $0 == "!" || $0 == "#" }) {
                return String(fullReference[..<separatorIndex])
            }

            return fullReference
        }

        if let relativeReference = references?.relative {
            return relativeReference
        }

        if let projectId {
            return "Project #\(projectId)"
        }

        return "GitLab"
    }

    private func mergeRequestStatus(for mergeRequest: GitLabRESTMergeRequest) -> GitLabMergeRequestStatus {
        if mergeRequest.draft == true || mergeRequest.workInProgress == true {
            return .draft
        }

        if mergeRequest.reviewers.isEmpty == false || mergeRequest.labels.contains(where: { $0.localizedCaseInsensitiveContains("review") }) {
            return .reviewing
        }

        if mergeRequest.detailedMergeStatus == "mergeable" || mergeRequest.mergeStatus == "can_be_merged" {
            return .approved
        }

        return .opened
    }

    private func issuePriority(for labels: [String]) -> GitLabIssuePriority {
        let normalizedLabels = labels.map { $0.lowercased() }
        if normalizedLabels.contains(where: { $0.contains("urgent") || $0.contains("critical") }) {
            return .urgent
        }

        if normalizedLabels.contains(where: { $0.contains("high") }) {
            return .high
        }

        if normalizedLabels.contains(where: { $0.contains("medium") }) {
            return .medium
        }

        return .low
    }

    private func notificationKind(for notification: GitLabRESTNotification) -> GitLabNotificationKind {
        let action = notification.actionName?.lowercased() ?? ""
        let targetType = notification.targetType?.lowercased() ?? notification.target?.type?.lowercased() ?? ""

        if action.contains("mentioned") {
            return .mentioned
        }

        if action.contains("assigned") {
            return .assigned
        }

        if targetType.contains("merge") || action.contains("review") {
            return .reviewRequested
        }

        if targetType.contains("pipeline") {
            return .pipelineFailed
        }

        return .mentioned
    }

    private func pipelineStatus(for status: GitLabRESTPipeline.Status?) -> GitLabPipelineStatus {
        switch status {
        case .running, .pending, .created, .waitingForResource, .preparing:
            return .running
        case .success:
            return .passed
        case .failed:
            return .failed
        case .canceled, .skipped, .manual, .scheduled, nil:
            return .canceled
        }
    }

    private func relativeTime(from dateString: String?) -> String {
        guard let dateString else {
            return "-"
        }

        let date = isoDateFormatter.date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
        guard let date else {
            return dateString
        }

        return date.formatted(.relative(presentation: .named))
    }
}

enum GitLabServiceError: LocalizedError, Equatable {
    case missingSettings
    case invalidURL
    case invalidResponse
    case unauthorized
    case requestFailed(Int)

    var errorDescription: String? {
        switch self {
        case .missingSettings:
            return "GitLab URL and personal access token are required."
        case .invalidURL:
            return "The GitLab URL is invalid."
        case .invalidResponse:
            return "GitLab returned an invalid response."
        case .unauthorized:
            return "GitLab rejected the personal access token."
        case let .requestFailed(statusCode):
            return "GitLab request failed with status \(statusCode)."
        }
    }
}
