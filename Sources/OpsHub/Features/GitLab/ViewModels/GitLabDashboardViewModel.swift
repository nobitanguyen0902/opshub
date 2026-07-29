import Foundation

/// Coordinates GitLab dashboard loading state and formatted dashboard data.
@MainActor
final class GitLabDashboardViewModel: ObservableObject {
    static let autoRefreshInterval: Duration = .seconds(5 * 60)

    @Published var selection = GitLabWorkspaceSelection()
    @Published var selectedScope: GitLabProjectScope = .allProjects
    @Published var selectedIssueTab: GitLabIssueTab = .assignedToMe
    @Published private var sectionFilters: [GitLabWorkspaceSection: GitLabWorkspaceFilter] = [:]
    @Published private(set) var projects: [GitLabProjectSummary] = []
    @Published private(set) var mergeRequests: [GitLabMergeRequest] = []
    @Published private(set) var mergeReviews: [GitLabMergeRequest] = []
    @Published private(set) var issues: [GitLabIssue] = []
    @Published private(set) var pipelines: [GitLabPipeline] = []
    @Published private(set) var sectionStates: [GitLabWorkspaceSection: GitLabSectionLoadState] = [:]
    @Published private(set) var sectionUpdatedAt: [GitLabWorkspaceSection: Date] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var loadWarning: String?
    @Published private(set) var pipelineWarning: String?
    @Published private(set) var pipelineDetails: [GitLabPipelineKey: GitLabPipelineDetailsLoadState] = [:]
    @Published private(set) var pipelineStageActions: [GitLabPipelineStageKey: GitLabPipelineStageActionState] = [:]
    @Published private(set) var pipelineActionNotice: GitLabPipelineActionNotice?

    private let service: any GitLabServicing
    private var loadingScope: GitLabProjectScope?
    private var loadedScope: GitLabProjectScope?
    private var loadingPipelineDetails: Set<GitLabPipelineKey> = []

    init(
        service: any GitLabServicing = GitLabService()
    ) {
        self.service = service
    }

    var isEmpty: Bool {
        mergeRequests.isEmpty && mergeReviews.isEmpty && issues.isEmpty && pipelines.isEmpty
    }

    var selectedSection: GitLabWorkspaceSection {
        get { selection.section }
        set { selection.section = newValue }
    }

    var searchText: String {
        get { filter(for: selectedSection).searchText }
        set {
            var updatedFilter = filter(for: selectedSection)
            updatedFilter.searchText = newValue
            setFilter(updatedFilter, for: selectedSection)
        }
    }

    var hasStaleData: Bool {
        sectionStates.values.contains { state in
            if case .stale = state { return true }
            return false
        }
    }

    var overviewLoadState: GitLabSectionLoadState {
        if isLoading {
            return isEmpty ? .initialLoading : .refreshing
        }

        let states = GitLabWorkspaceSection.allCases
            .filter { $0 != .overview }
            .map(loadState)
        let message = loadWarning ?? "GitLab activity could not be loaded."
        if isEmpty, states.contains(where: { if case .failed = $0 { true } else { false } }) {
            return .failed(message)
        }
        if states.contains(where: {
            if case .failed = $0 { return true }
            if case .stale = $0 { return true }
            return false
        }) {
            return .stale(message)
        }
        return .loaded
    }

    var summaryMetrics: [GitLabSummaryMetric] {
        let scopedReviews = mergeReviews.filter { selectedScope.includes(projectName: $0.project) }
        let scopedMergeRequests = mergeRequests.filter {
            selectedScope.includes(projectName: $0.project)
        }
        let assignedIssues = issues.filter {
            $0.isAssignedToMe && selectedScope.includes(projectName: $0.project)
        }
        let failedPipelines = pipelines.filter {
            $0.status == .failed && selectedScope.includes(projectName: $0.project)
        }
        return [
            GitLabSummaryMetric(
                kind: .awaitingReview,
                title: "Waiting for my review",
                value: scopedReviews.count,
                systemImage: "checkmark.bubble",
                semantic: .warning
            ),
            GitLabSummaryMetric(
                kind: .mergeRequests,
                title: "Merge Requests",
                value: scopedMergeRequests.count,
                systemImage: "arrow.triangle.branch",
                semantic: .information
            ),
            GitLabSummaryMetric(
                kind: .assignedToMe,
                title: "Assigned to me",
                value: assignedIssues.count,
                systemImage: "person.crop.circle.badge.checkmark",
                semantic: .information
            ),
            GitLabSummaryMetric(
                kind: .failedPipelines,
                title: "Failed pipelines",
                value: failedPipelines.count,
                systemImage: "xmark.circle",
                semantic: .error
            )
        ]
    }

    var actionQueue: [GitLabWorkItemPresentation] {
        filterOverview(GitLabActionQueueBuilder.build(
            reviews: mergeReviews,
            issues: issues,
            pipelines: pipelines,
            notifications: [],
            scope: selectedScope
        ))
    }

    var mergeRequestPreview: [GitLabWorkItemPresentation] {
        let scopedItems = mergeRequests.filter { selectedScope.includes(projectName: $0.project) }
        let presentations = GitLabWorkspaceFiltering.sortMergeRequests(scopedItems, by: .updatedDescending).map {
            GitLabWorkItemPresentation(mergeRequest: $0, context: .mergeRequest)
        }
        return Array(filterOverview(presentations).prefix(5))
    }

    var pipelinePreview: [GitLabWorkItemPresentation] {
        let scopedItems = pipelines.filter { selectedScope.includes(projectName: $0.project) }
        let presentations = GitLabWorkspaceFiltering.sortPipelines(scopedItems)
            .map(GitLabWorkItemPresentation.init(pipeline:))
        return Array(filterOverview(presentations).prefix(5))
    }

    var visibleMergeRequests: [GitLabMergeRequest] {
        GitLabWorkspaceFiltering.sortMergeRequests(
            GitLabWorkspaceFiltering.mergeRequests(
                mergeRequests,
                scope: selectedScope,
                filter: filter(for: .mergeRequests)
            ),
            by: .updatedDescending
        )
    }

    var visibleMergeReviews: [GitLabMergeRequest] {
        GitLabWorkspaceFiltering.sortMergeRequests(
            GitLabWorkspaceFiltering.mergeRequests(
                mergeReviews,
                scope: selectedScope,
                filter: filter(for: .reviews)
            ),
            by: .updatedDescending
        )
    }

    var visibleIssues: [GitLabIssue] {
        GitLabWorkspaceFiltering.sortIssues(
            GitLabWorkspaceFiltering.issues(
                issues,
                scope: selectedScope,
                tab: selectedIssueTab,
                filter: filter(for: .issues)
            )
        )
    }

    var visiblePipelines: [GitLabPipeline] {
        GitLabWorkspaceFiltering.sortPipelines(
            GitLabWorkspaceFiltering.pipelines(
                pipelines,
                scope: selectedScope,
                filter: filter(for: .pipelines)
            )
        )
    }

    func filter(for section: GitLabWorkspaceSection) -> GitLabWorkspaceFilter {
        sectionFilters[section] ?? GitLabWorkspaceFilter()
    }

    func setFilter(_ filter: GitLabWorkspaceFilter, for section: GitLabWorkspaceSection) {
        sectionFilters[section] = filter
    }

    func clearFilters(for section: GitLabWorkspaceSection) {
        sectionFilters[section] = GitLabWorkspaceFilter()
    }

    func loadState(for section: GitLabWorkspaceSection) -> GitLabSectionLoadState {
        sectionStates[section] ?? .idle
    }

    func badgeCount(for section: GitLabWorkspaceSection) -> Int {
        switch section {
        case .overview:
            0
        case .mergeRequests:
            visibleMergeRequests.count
        case .reviews:
            visibleMergeReviews.count
        case .issues:
            visibleIssues.count
        case .pipelines:
            visiblePipelines.filter { $0.status == .failed }.count
        }
    }

    func activate(_ metric: GitLabSummaryMetricKind) {
        switch metric {
        case .awaitingReview:
            selectedSection = .reviews
            clearFilters(for: .reviews)
        case .mergeRequests:
            selectedSection = .mergeRequests
            clearFilters(for: .mergeRequests)
        case .assignedToMe:
            selectedSection = .issues
            selectedIssueTab = .assignedToMe
            clearFilters(for: .issues)
        case .failedPipelines:
            selectedSection = .pipelines
            setFilter(
                GitLabWorkspaceFilter(statuses: [GitLabPipelineStatus.failed.rawValue]),
                for: .pipelines
            )
        }
    }

    func select(_ item: GitLabWorkspaceItemID?) {
        selection.item = item
    }

    func pipelineDetailsState(for pipeline: GitLabPipeline) -> GitLabPipelineDetailsLoadState {
        pipelineDetails[pipelineKey(for: pipeline)] ?? .idle
    }

    func stageActionState(
        for stage: GitLabPipelineStage,
        pipeline: GitLabPipeline
    ) -> GitLabPipelineStageActionState {
        pipelineStageActions[stageKey(for: stage, pipeline: pipeline)] ?? .idle
    }

    func loadPipelineDetails(_ pipeline: GitLabPipeline, force: Bool = false) async {
        let key = pipelineKey(for: pipeline)
        guard pipeline.projectID > 0 else {
            pipelineDetails[key] = .failed("This pipeline is missing its GitLab project identifier.")
            return
        }
        guard loadingPipelineDetails.contains(key) == false else { return }
        if !force, case .loaded = pipelineDetails[key] {
            return
        }

        let previousState = pipelineDetails[key]
        loadingPipelineDetails.insert(key)
        if case .loaded = previousState {
            // Keep the current stage grid visible while polling an active pipeline.
        } else {
            pipelineDetails[key] = .loading
        }
        defer { loadingPipelineDetails.remove(key) }

        do {
            let jobs = try await service.pipelineJobs(
                projectID: pipeline.projectID,
                pipelineID: pipeline.id
            )
            pipelineDetails[key] = .loaded(
                GitLabPipelineDetails(pipeline: key, jobs: jobs)
            )
        } catch {
            if case .loaded = previousState {
                pipelineDetails[key] = previousState
            } else {
                pipelineDetails[key] = .failed(errorMessage(error))
            }
        }
    }

    func perform(
        _ action: GitLabPipelineStageAction,
        on stage: GitLabPipelineStage,
        pipeline: GitLabPipeline,
        pollIntervals: [Duration] = [
            .seconds(2), .seconds(3), .seconds(5), .seconds(10), .seconds(10)
        ]
    ) async {
        let actionKey = stageKey(for: stage, pipeline: pipeline)
        guard pipelineStageActions[actionKey]?.isRunning != true else { return }
        guard pipeline.allowsMutationActions else {
            pipelineActionNotice = GitLabPipelineActionNotice(
                message: pipeline.isTag == true
                    ? GitLabPipelineActionError.tagPipelineReadOnly.localizedDescription
                    : "Pipeline type is unavailable, so actions are disabled.",
                severity: .error
            )
            return
        }

        pipelineStageActions[actionKey] = .running(action)

        do {
            let freshJobs = try await service.pipelineJobs(
                projectID: pipeline.projectID,
                pipelineID: pipeline.id
            )
            let refreshedDetails = GitLabPipelineDetails(
                pipeline: pipelineKey(for: pipeline),
                jobs: freshJobs
            )
            pipelineDetails[refreshedDetails.pipeline] = .loaded(refreshedDetails)
            guard let refreshedStage = refreshedDetails.stages.first(where: { $0.name == stage.name }) else {
                throw GitLabPipelineActionError.actionUnavailable
            }

            let jobs = refreshedStage.actionableJobs(for: action)
            guard jobs.isEmpty == false else {
                throw GitLabPipelineActionError.actionUnavailable
            }

            var failedCount = 0
            var lastError: (any Error)?
            for job in jobs {
                do {
                    _ = try await perform(action, on: job, projectID: pipeline.projectID)
                } catch {
                    failedCount += 1
                    lastError = error
                }
            }

            if failedCount > 0 {
                let message = failedCount == jobs.count
                    ? errorMessage(lastError ?? GitLabPipelineActionError.actionUnavailable)
                    : "\(jobs.count - failedCount)/\(jobs.count) jobs accepted by GitLab."
                pipelineStageActions[actionKey] = .failed(message)
                pipelineActionNotice = GitLabPipelineActionNotice(
                    message: message,
                    severity: .error
                )
                await loadPipelineDetails(pipeline, force: true)
                return
            }

            pipelineActionNotice = GitLabPipelineActionNotice(
                message: "\(action.rawValue) requested for \(stage.name).",
                severity: .neutral
            )
            await monitor(
                stageName: stage.name,
                pipeline: pipeline,
                intervals: pollIntervals
            )
            pipelineStageActions[actionKey] = .idle
        } catch {
            let message = errorMessage(error)
            pipelineStageActions[actionKey] = .failed(message)
            pipelineActionNotice = GitLabPipelineActionNotice(
                message: message,
                severity: .error
            )
        }
    }

    func dismissPipelineActionNotice(_ id: UUID) {
        guard pipelineActionNotice?.id == id else { return }
        pipelineActionNotice = nil
    }

    func loadDashboard() async {
        let scope = selectedScope
        guard loadedScope != scope else { return }
        await refresh()
    }

    func autoRefresh(every interval: Duration = autoRefreshInterval) async {
        while Task.isCancelled == false {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
            guard Task.isCancelled == false else { return }
            await refresh()
        }
    }

    func refresh() async {
        let scope = selectedScope
        guard loadingScope != scope else { return }
        loadingScope = scope
        isLoading = true
        defer {
            if loadingScope == scope {
                loadingScope = nil
                isLoading = false
            }
        }

        await service.invalidateProjectCatalog()

        beginLoading(.mergeRequests, hasData: mergeRequests.isEmpty == false)
        beginLoading(.reviews, hasData: mergeReviews.isEmpty == false)
        beginLoading(.issues, hasData: issues.isEmpty == false)
        beginLoading(.pipelines, hasData: pipelines.isEmpty == false)

        async let projectsTask = loadSection { try await self.service.projects() }
        async let mergeRequestsTask = loadSection { try await self.service.mergeRequests(scope: scope) }
        async let mergeReviewsTask = loadSection { try await self.service.mergeReviews(scope: scope) }
        async let issuesTask = loadSection { try await self.service.issues(scope: scope) }
        async let pipelinesTask = loadSection { try await self.service.pipelineBatch(scope: scope) }

        let projectsResult = await projectsTask
        let mergeRequestsResult = await mergeRequestsTask
        let mergeReviewsResult = await mergeReviewsTask
        let issuesResult = await issuesTask
        let pipelinesResult = await pipelinesTask

        guard selectedScope == scope else { return }

        if let loadedProjects = projectsResult.value {
            projects = loadedProjects
        }
        let mergeRequestsSucceeded = apply(
            mergeRequestsResult,
            section: .mergeRequests,
            hadData: mergeRequests.isEmpty == false
        ) { mergeRequests = $0 }
        let mergeReviewsSucceeded = apply(
            mergeReviewsResult,
            section: .reviews,
            hadData: mergeReviews.isEmpty == false
        ) { mergeReviews = $0 }
        let issuesSucceeded = apply(
            issuesResult,
            section: .issues,
            hadData: issues.isEmpty == false
        ) { issues = $0 }
        let pipelinesSucceeded = apply(
            pipelinesResult,
            section: .pipelines,
            hadData: pipelines.isEmpty == false
        ) { batch in
            pipelines = batch.pipelines
            let activeKeys = Set(batch.pipelines.map(pipelineKey))
            pipelineDetails = pipelineDetails.filter { activeKeys.contains($0.key) }
            pipelineStageActions = pipelineStageActions.filter {
                activeKeys.contains($0.key.pipeline)
            }
            pipelineWarning = batch.failedProjects.isEmpty
                ? nil
                : "Could not load pipelines for: \(batch.failedProjects.joined(separator: ", "))."
        }
        loadWarning = loadWarning(for: [
            projectsResult.error,
            mergeRequestsResult.error,
            mergeReviewsResult.error,
            issuesResult.error,
            pipelinesResult.error
        ])
        if projectsResult.value != nil
            || mergeRequestsSucceeded
            || mergeReviewsSucceeded
            || issuesSucceeded
            || pipelinesSucceeded {
            lastUpdated = .now
            loadedScope = scope
        }
    }

    private func beginLoading(_ section: GitLabWorkspaceSection, hasData: Bool) {
        sectionStates[section] = hasData ? .refreshing : .initialLoading
    }

    private func filterOverview(
        _ items: [GitLabWorkItemPresentation]
    ) -> [GitLabWorkItemPresentation] {
        let query = filter(for: .overview).searchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return items }
        return items.filter { item in
            [item.reference, item.title, item.project, item.status.title]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    @discardableResult
    private func apply<Value: Sendable>(
        _ result: Result<Value, any Error>,
        section: GitLabWorkspaceSection,
        hadData: Bool,
        assign: (Value) -> Void
    ) -> Bool {
        switch result {
        case let .success(value):
            assign(value)
            sectionStates[section] = .loaded
            sectionUpdatedAt[section] = .now
            return true
        case let .failure(error):
            let message = errorMessage(error)
            sectionStates[section] = hadData ? .stale(message) : .failed(message)
            return false
        }
    }

    private func loadSection<Value: Sendable>(
        _ load: @escaping () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await load())
        } catch {
            return .failure(error)
        }
    }

    private func loadWarning(for errors: [Error?]) -> String? {
        let errors = errors.compactMap { $0 }
        guard errors.isEmpty == false else {
            return nil
        }

        if errors.count == 1, let description = (errors.first as? LocalizedError)?.errorDescription {
            return description
        }

        return "Some GitLab sections could not be loaded."
    }

    private func errorMessage(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func pipelineKey(for pipeline: GitLabPipeline) -> GitLabPipelineKey {
        GitLabPipelineKey(projectID: pipeline.projectID, pipelineID: pipeline.id)
    }

    private func stageKey(
        for stage: GitLabPipelineStage,
        pipeline: GitLabPipeline
    ) -> GitLabPipelineStageKey {
        GitLabPipelineStageKey(pipeline: pipelineKey(for: pipeline), name: stage.name)
    }

    private func perform(
        _ action: GitLabPipelineStageAction,
        on job: GitLabJob,
        projectID: Int
    ) async throws -> GitLabJob {
        switch action {
        case .build:
            try await service.playJob(projectID: projectID, jobID: job.id)
        case .retry:
            try await service.retryJob(projectID: projectID, jobID: job.id)
        case .cancel:
            try await service.cancelJob(projectID: projectID, jobID: job.id)
        }
    }

    private func monitor(
        stageName: String,
        pipeline: GitLabPipeline,
        intervals: [Duration]
    ) async {
        for interval in [.zero] + intervals {
            if interval != .zero {
                do {
                    try await Task.sleep(for: interval)
                } catch {
                    return
                }
            }

            await loadPipelineDetails(pipeline, force: true)
            guard case let .loaded(details) = pipelineDetailsState(for: pipeline),
                  let stage = details.stages.first(where: { $0.name == stageName }) else {
                continue
            }

            switch stage.status {
            case .success:
                pipelineActionNotice = GitLabPipelineActionNotice(
                    message: "\(stage.name) completed successfully.",
                    severity: .success
                )
                return
            case .failed:
                let reason = stage.jobs.compactMap(\.failureReason).first
                pipelineActionNotice = GitLabPipelineActionNotice(
                    message: reason.map { "\(stage.name) failed: \($0)." } ?? "\(stage.name) failed.",
                    severity: .error
                )
                return
            case .canceled:
                pipelineActionNotice = GitLabPipelineActionNotice(
                    message: "\(stage.name) was canceled.",
                    severity: .neutral
                )
                return
            case .idle, .manual, .pending, .running:
                continue
            }
        }
    }

}

private extension Result {
    var value: Success? {
        if case let .success(value) = self {
            return value
        }

        return nil
    }

    var error: Failure? {
        if case let .failure(error) = self {
            return error
        }

        return nil
    }
}
