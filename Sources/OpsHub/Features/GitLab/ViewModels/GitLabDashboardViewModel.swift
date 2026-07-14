import Foundation

/// Coordinates GitLab dashboard loading state and formatted dashboard data.
@MainActor
final class GitLabDashboardViewModel: ObservableObject {
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

    private let service: any GitLabServicing
    private var loadingScope: GitLabProjectScope?
    private var loadedScope: GitLabProjectScope?

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

    func loadDashboard() async {
        let scope = selectedScope
        guard loadedScope != scope else { return }
        await refresh()
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
