import Foundation

/// Provides GitLab dashboard data and settings validation.
protocol GitLabServicing: Sendable {
    func projects() async throws -> [GitLabProjectSummary]
    func invalidateProjectCatalog() async
    func mergeRequests() async throws -> [GitLabMergeRequest]
    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest]
    func mergeReviews() async throws -> [GitLabMergeRequest]
    func mergeReviews(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest]
    func issues() async throws -> [GitLabIssue]
    func issues(scope: GitLabProjectScope) async throws -> [GitLabIssue]
    func notifications() async throws -> [GitLabNotification]
    func notifications(scope: GitLabProjectScope) async throws -> [GitLabNotification]
    func pipelines() async throws -> [GitLabPipeline]
    func pipelines(scope: GitLabProjectScope) async throws -> [GitLabPipeline]
    func pipelineBatch(scope: GitLabProjectScope) async throws -> GitLabPipelineBatch
    func testConnection(settings: GitLabSettings) async throws -> GitLabConnectionTestResult
}

extension GitLabServicing {
    func projects() async throws -> [GitLabProjectSummary] { [] }
    func invalidateProjectCatalog() async {}

    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        try await mergeRequests().filter { scope.includes(projectName: $0.project) }
    }

    func mergeReviews(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        try await mergeReviews().filter { scope.includes(projectName: $0.project) }
    }

    func issues(scope: GitLabProjectScope) async throws -> [GitLabIssue] {
        try await issues().filter { scope.includes(projectName: $0.project) }
    }

    func notifications(scope: GitLabProjectScope) async throws -> [GitLabNotification] {
        try await notifications().filter { scope.includes(projectName: $0.project) }
    }

    func pipelines(scope: GitLabProjectScope) async throws -> [GitLabPipeline] {
        try await pipelines().filter { scope.includes(projectName: $0.project) }
    }

    func pipelineBatch(scope: GitLabProjectScope) async throws -> GitLabPipelineBatch {
        GitLabPipelineBatch(pipelines: try await pipelines(scope: scope), failedProjects: [])
    }
}

/// Minimal HTTP client abstraction used by the GitLab REST service and tests.
protocol GitLabHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: GitLabHTTPClient {}

private actor GitLabProjectCatalogCache {
    private var loadTask: Task<[GitLabProject], any Error>?
    private var value: [GitLabProject]?
    private var generation = 0

    func invalidate() {
        generation += 1
        loadTask?.cancel()
        loadTask = nil
        value = nil
    }

    func load(
        operation: @escaping @Sendable () async throws -> [GitLabProject]
    ) async throws -> [GitLabProject] {
        if let value {
            return value
        }

        if let loadTask {
            return try await loadTask.value
        }

        let loadGeneration = generation
        let task = Task { try await operation() }
        loadTask = task
        defer {
            if generation == loadGeneration {
                loadTask = nil
            }
        }
        let loadedValue = try await task.value
        if generation == loadGeneration {
            value = loadedValue
        }
        return loadedValue
    }
}

private enum GitLabPipelineProjectResult: Sendable {
    case success([GitLabPipeline])
    case failure(String)
}

/// GitLab REST-backed dashboard data source.
struct GitLabService: GitLabServicing, DevRoomServicing, DevRoomMemberServicing, @unchecked Sendable {
    private let settingsStore: any GitLabSettingsStoring
    private let httpClient: any GitLabHTTPClient
    private let now: @Sendable () -> Date
    private let projectCatalogCache: GitLabProjectCatalogCache

    init(
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore(),
        httpClient: any GitLabHTTPClient = URLSession.shared,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.settingsStore = settingsStore
        self.httpClient = httpClient
        self.now = now
        projectCatalogCache = GitLabProjectCatalogCache()
    }

    func projects() async throws -> [GitLabProjectSummary] {
        let projects = try await loadProjectCatalog()
        return projects.map(mapProjectSummary)
    }

    func invalidateProjectCatalog() async {
        await projectCatalogCache.invalidate()
    }

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

    func mergeRequests(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        try await mergeRequests().filter { scope.includes(projectName: $0.project) }
    }

    func mergeReviews() async throws -> [GitLabMergeRequest] {
        try await mergeRequests(scope: "reviews_for_me")
    }

    func mergeReviews(scope: GitLabProjectScope) async throws -> [GitLabMergeRequest] {
        try await mergeReviews().filter { scope.includes(projectName: $0.project) }
    }

    private func mergeRequests(scope: String) async throws -> [GitLabMergeRequest] {
        let settings = try configuredSettings()
        let request = try makeRequest(
            settings: settings,
            path: "merge_requests",
            queryItems: [
                URLQueryItem(name: "scope", value: scope),
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
        let updatedAfter = issueUpdatedAfterDate()
        let workflowIssuesRequest = try makeWorkflowProjectIssuesRequest(
            settings: settings,
            queryItems: [
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "updated_after", value: updatedAfter),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "with_labels_details", value: "true"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        let assignedIssuesRequest = try makeRequest(
            settings: settings,
            path: "issues",
            queryItems: [
                URLQueryItem(name: "scope", value: "assigned_to_me"),
                URLQueryItem(name: "state", value: "opened"),
                URLQueryItem(name: "updated_after", value: updatedAfter),
                URLQueryItem(name: "order_by", value: "updated_at"),
                URLQueryItem(name: "sort", value: "desc"),
                URLQueryItem(name: "with_labels_details", value: "true"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )

        async let loadedWorkflowIssues: [GitLabRESTIssue] = sendAllPages(workflowIssuesRequest)
        async let loadedAssignedIssues: [GitLabRESTIssue] = sendAllPages(assignedIssuesRequest)
        let (workflowIssues, assignedIssues) = try await (loadedWorkflowIssues, loadedAssignedIssues)
        let assignedIssueIDs = Set(assignedIssues.map(\.id))
        let workflowIssueIDs = Set(workflowIssues.map(\.id))
        let combinedIssues = workflowIssues + assignedIssues.filter { workflowIssueIDs.contains($0.id) == false }

        return combinedIssues.map { issue in
            mapIssue(
                issue,
                isAssignedToMe: assignedIssueIDs.contains(issue.id),
                isWorkflowProject: workflowIssueIDs.contains(issue.id)
            )
        }
    }

    func issues(scope: GitLabProjectScope) async throws -> [GitLabIssue] {
        try await issues().filter { scope.includes(projectName: $0.project) }
    }

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

    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        let settings = try configuredSettings()
        let request = try makeProjectRequest(
            settings: settings,
            projectPath: projectPath,
            suffix: "members/all",
            queryItems: [URLQueryItem(name: "per_page", value: "100")]
        )
        let members: [GitLabProjectMember] = try await sendAllPages(request)
        return members.map {
            DevRoomProjectMember(
                id: $0.id,
                username: $0.username,
                name: $0.name,
                avatarURL: $0.avatarUrl,
                accessLevel: $0.accessLevel
            )
        }
        .sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return comparison == .orderedSame
                ? $0.id < $1.id
                : comparison == .orderedAscending
        }
    }

    private func issueUpdatedAfterDate() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let oneMonthAgo = calendar.date(byAdding: .month, value: -1, to: now()) ?? now()
        return isoDateString(from: oneMonthAgo)
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

    func notifications(scope: GitLabProjectScope) async throws -> [GitLabNotification] {
        try await notifications().filter { scope.includes(projectName: $0.project) }
    }

    func pipelines() async throws -> [GitLabPipeline] {
        try await pipelines(scope: .allProjects)
    }

    func pipelines(scope: GitLabProjectScope) async throws -> [GitLabPipeline] {
        try await pipelineBatch(scope: scope).pipelines
    }

    func pipelineBatch(scope: GitLabProjectScope) async throws -> GitLabPipelineBatch {
        let settings = try configuredSettings()
        let loadedProjects = try await loadProjectCatalog()
        let projects = loadedProjects.filter { project in
            scope.includes(projectName: projectDisplayName(project))
        }
        let results = try await withThrowingTaskGroup(of: GitLabPipelineProjectResult.self) { group in
            for project in projects.prefix(5) {
                let request = try makeRequest(
                    settings: settings,
                    path: "projects/\(project.id)/pipelines",
                    queryItems: [URLQueryItem(name: "per_page", value: "5")]
                )
                let projectName = projectDisplayName(project)
                group.addTask {
                    do {
                        let response: [GitLabRESTPipeline] = try await send(request)
                        return .success(response.map { mapPipeline($0, project: project) })
                    } catch {
                        return .failure(projectName)
                    }
                }
            }

            var values: [GitLabPipelineProjectResult] = []
            for try await result in group { values.append(result) }
            return values
        }
        var pipelines: [GitLabPipeline] = []
        var failedProjects: [String] = []
        for result in results {
            switch result {
            case let .success(values): pipelines.append(contentsOf: values)
            case let .failure(project): failedProjects.append(project)
            }
        }

        return GitLabPipelineBatch(
            pipelines: Array(pipelines.sorted { $0.id > $1.id }.prefix(20)),
            failedProjects: failedProjects.sorted()
        )
    }

    private func loadProjectCatalog() async throws -> [GitLabProject] {
        try await projectCatalogCache.load {
            let settings = try configuredSettings()
            let request = try makeRequest(
                settings: settings,
                path: "projects",
                queryItems: [
                    URLQueryItem(name: "membership", value: "true"),
                    URLQueryItem(name: "simple", value: "true"),
                    URLQueryItem(name: "order_by", value: "last_activity_at"),
                    URLQueryItem(name: "sort", value: "desc"),
                    URLQueryItem(name: "per_page", value: "100")
                ]
            )
            let projects: [GitLabProject] = try await sendAllPages(request)
            return projects
        }
    }

    private func mapProjectSummary(_ project: GitLabProject) -> GitLabProjectSummary {
        GitLabProjectSummary(
            id: project.id,
            nameWithNamespace: projectDisplayName(project),
            webURL: project.webUrl
        )
    }

    private func projectDisplayName(_ project: GitLabProject) -> String {
        project.nameWithNamespace
            ?? project.pathWithNamespace
            ?? project.name
            ?? project.path
            ?? "Project #\(project.id)"
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
        try makeProjectRequest(
            settings: settings,
            projectPath: projectPath,
            suffix: "issues",
            queryItems: queryItems
        )
    }

    private func makeProjectRequest(
        settings: GitLabSettings,
        projectPath: String,
        suffix: String,
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

        components.percentEncodedPath += "/\(encodedProject)/\(suffix)"
        components.queryItems = queryItems
        guard let url = components.url else {
            throw GitLabServiceError.invalidURL
        }

        request.url = url
        return request
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await httpClient.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401, 403:
            throw GitLabServiceError.unauthorized
        default:
            throw GitLabServiceError.requestFailed(httpResponse.statusCode)
        }
    }

    private func sendAllPages<Response: Decodable>(_ initialRequest: URLRequest) async throws -> [Response] {
        var request = initialRequest
        var values: [Response] = []

        while true {
            let (data, response) = try await httpClient.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw GitLabServiceError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200..<300:
                values.append(contentsOf: try JSONDecoder().decode([Response].self, from: data))
            case 401, 403:
                throw GitLabServiceError.unauthorized
            default:
                throw GitLabServiceError.requestFailed(httpResponse.statusCode)
            }

            guard let nextPage = httpResponse.value(forHTTPHeaderField: "X-Next-Page"),
                  nextPage.isEmpty == false else {
                return values
            }

            guard let requestURL = request.url,
                  var components = URLComponents(url: requestURL, resolvingAgainstBaseURL: false) else {
                throw GitLabServiceError.invalidURL
            }
            var queryItems = components.queryItems ?? []
            queryItems.removeAll { $0.name == "page" }
            queryItems.append(URLQueryItem(name: "page", value: nextPage))
            components.queryItems = queryItems
            guard let nextURL = components.url else {
                throw GitLabServiceError.invalidURL
            }
            request.url = nextURL
        }
    }

    private func mapMergeRequest(_ mergeRequest: GitLabRESTMergeRequest) -> GitLabMergeRequest {
        GitLabMergeRequest(
            id: mergeRequest.id,
            iid: mergeRequest.iid,
            title: mergeRequest.title,
            project: projectName(from: mergeRequest.references, projectId: mergeRequest.projectId),
            status: mergeRequestStatus(for: mergeRequest),
            authorName: mergeRequest.author?.name ?? mergeRequest.author?.username,
            authorAvatarURL: mergeRequest.author?.avatarUrl,
            assigneeName: mergeRequest.assignees.first?.name
                ?? mergeRequest.assignees.first?.username,
            assigneeAvatarURL: mergeRequest.assignees.first?.avatarUrl,
            updatedAt: date(from: mergeRequest.updatedAt),
            updatedTime: relativeTime(from: mergeRequest.updatedAt),
            webURL: mergeRequest.webUrl
        )
    }

    private func mapIssue(
        _ issue: GitLabRESTIssue,
        isAssignedToMe: Bool,
        isWorkflowProject: Bool
    ) -> GitLabIssue {
        GitLabIssue(
            id: issue.id,
            iid: issue.iid,
            title: issue.title,
            project: projectName(from: issue.references, projectId: issue.projectId),
            priority: issuePriority(for: issue.labels.map(\.name)),
            labels: issue.labels.map(\.name),
            labelDetails: issue.labels.map {
                GitLabLabel(name: $0.name, color: $0.color, textColor: $0.textColor)
            },
            isAssignedToMe: isAssignedToMe,
            isWorkflowProject: isWorkflowProject,
            assigneeName: issue.assignees.first?.name ?? issue.assignees.first?.username,
            assigneeAvatarURL: issue.assignees.first?.avatarUrl,
            updatedAt: date(from: issue.updatedAt),
            updatedTime: relativeTime(from: issue.updatedAt),
            webURL: issue.webUrl
        )
    }

    private func mapNotification(_ notification: GitLabRESTNotification) -> GitLabNotification {
        let project = notification.project?.nameWithNamespace ?? notification.project?.name ?? "GitLab"
        return GitLabNotification(
            id: notification.id,
            title: notification.target?.title ?? notification.body ?? notification.actionName ?? "GitLab notification",
            project: project,
            kind: notificationKind(for: notification),
            authorName: notification.author?.name ?? notification.author?.username,
            authorAvatarURL: notification.author?.avatarUrl,
            updatedAt: date(from: notification.createdAt),
            updatedTime: relativeTime(from: notification.createdAt),
            webURL: notification.targetUrl ?? notification.target?.url,
            targetResourceKey: notificationResourceKey(notification, project: project)
        )
    }

    private func notificationResourceKey(
        _ notification: GitLabRESTNotification,
        project: String
    ) -> GitLabResourceKey? {
        guard let targetID = notification.target?.id else { return nil }
        let targetType = (notification.targetType ?? notification.target?.type ?? "")
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
        let kind: GitLabResourceKind
        if targetType.contains("mergerequest") {
            kind = .mergeRequest
        } else if targetType.contains("issue") {
            kind = .issue
        } else if targetType.contains("pipeline") {
            kind = .pipeline
        } else {
            return nil
        }
        return GitLabResourceKey(kind: kind, project: project, id: targetID)
    }

    private func mapPipeline(_ pipeline: GitLabRESTPipeline, project: GitLabProject) -> GitLabPipeline {
        GitLabPipeline(
            id: pipeline.id,
            project: project.nameWithNamespace ?? project.name ?? "Project #\(project.id)",
            branch: pipeline.ref ?? "-",
            status: pipelineStatus(for: pipeline.status),
            userName: pipeline.user?.name ?? pipeline.user?.username,
            userAvatarURL: pipeline.user?.avatarUrl,
            updatedAt: date(from: pipeline.updatedAt ?? pipeline.createdAt),
            updatedTime: relativeTime(from: pipeline.updatedAt ?? pipeline.createdAt),
            webURL: pipeline.webUrl
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

        let date = date(from: dateString)
        guard let date else {
            return dateString
        }

        return date.formatted(.relative(presentation: .named))
    }

    private func date(from dateString: String?) -> Date? {
        guard let dateString else { return nil }
        return makeISODateFormatter().date(from: dateString) ?? ISO8601DateFormatter().date(from: dateString)
    }

    private func isoDateString(from date: Date) -> String {
        makeISODateFormatter().string(from: date)
    }

    private func makeISODateFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

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
