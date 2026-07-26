import SwiftUI

/// Main GitLab dashboard screen with summary metrics and work item lists.
struct GitLabDashboardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var viewModel: GitLabDashboardViewModel

    init(viewModel: GitLabDashboardViewModel) {
        _viewModel = ObservedObject(wrappedValue: viewModel)
    }

    var body: some View {
        GitLabAdaptiveLayout { mode in
            VStack(alignment: .leading, spacing: 0) {
                header(mode: mode)
                    .padding(.horizontal, mode.pagePadding)
                    .padding(.top, mode.pagePadding)

                ScrollView {
                    VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xLarge) {
                        GitLabWorkspaceNavigation(
                            mode: mode,
                            selection: selectedSection,
                            badgeCount: viewModel.badgeCount
                        )
                        GitLabSummaryStrip(
                            metrics: viewModel.summaryMetrics,
                            mode: mode,
                            onSelect: viewModel.activate
                        )
                        warning
                        sectionContent(mode: mode)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.horizontal, mode.pagePadding)
                    .padding(.top, GitLabDesignTokens.Spacing.xLarge)
                    .padding(.bottom, mode.pagePadding)
                }
            }
            .background(GitLabDesignTokens.surfaceSecondary)
        }
        .navigationTitle("GitLab")
        .task(id: viewModel.selectedScope) {
            await viewModel.loadDashboard()
        }
        .task {
            await viewModel.autoRefresh()
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: viewModel.isLoading)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: viewModel.mergeRequests)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: viewModel.mergeReviews)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: viewModel.issues)
    }

    private func header(mode: GitLabWorkspaceLayoutMode) -> some View {
        GitLabWorkspaceHeader(
            mode: mode,
            projects: viewModel.projects,
            selectedScope: $viewModel.selectedScope,
            searchText: searchText,
            isRefreshing: viewModel.isLoading,
            hasStaleData: viewModel.hasStaleData,
            lastUpdated: viewModel.lastUpdated
        ) {
            Task { await viewModel.refresh() }
        }
    }

    @ViewBuilder
    private var warning: some View {
        if let loadWarning = viewModel.loadWarning {
            Label(loadWarning, systemImage: "exclamationmark.triangle")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control, isEmphasized: true)
        }
    }

    @ViewBuilder
    private func sectionContent(mode: GitLabWorkspaceLayoutMode) -> some View {
        switch viewModel.selectedSection {
        case .overview:
            GitLabOverviewView(
                mode: mode,
                actionQueue: viewModel.actionQueue,
                mergeRequests: viewModel.mergeRequestPreview,
                pipelines: viewModel.pipelinePreview,
                selectedItemID: viewModel.selection.item,
                loadState: viewModel.overviewLoadState,
                onSelect: viewModel.select,
                onShowSection: { viewModel.selectedSection = $0 },
                onRetry: refresh
            )
        case .mergeRequests:
            GitLabMergeRequestsView(
                mode: mode,
                items: viewModel.visibleMergeRequests.map {
                    GitLabWorkItemPresentation(mergeRequest: $0, context: .mergeRequest)
                },
                loadState: viewModel.loadState(for: .mergeRequests),
                filter: viewModel.filter(for: .mergeRequests),
                selectedItemID: viewModel.selection.item,
                onSelect: viewModel.select,
                onStatusChange: { statuses in
                    var filter = viewModel.filter(for: .mergeRequests)
                    filter.statuses = statuses
                    viewModel.setFilter(filter, for: .mergeRequests)
                },
                onClearFilters: { viewModel.clearFilters(for: .mergeRequests) },
                onRetry: refresh
            )
        case .reviews:
            GitLabReviewsView(
                mode: mode,
                items: viewModel.visibleMergeReviews.map {
                    GitLabWorkItemPresentation(mergeRequest: $0, context: .review)
                },
                loadState: viewModel.loadState(for: .reviews),
                filter: viewModel.filter(for: .reviews),
                selectedItemID: viewModel.selection.item,
                onSelect: viewModel.select,
                onStatusChange: { statuses in
                    var filter = viewModel.filter(for: .reviews)
                    filter.statuses = statuses
                    viewModel.setFilter(filter, for: .reviews)
                },
                onClearFilters: { viewModel.clearFilters(for: .reviews) },
                onRetry: refresh
            )
        case .issues:
            GitLabIssuesView(
                mode: mode,
                items: viewModel.visibleIssues.map(GitLabWorkItemPresentation.init(issue:)),
                loadState: viewModel.loadState(for: .issues),
                filter: viewModel.filter(for: .issues),
                selectedItemID: viewModel.selection.item,
                selectedTab: $viewModel.selectedIssueTab,
                onSelect: viewModel.select,
                onClearFilters: { viewModel.clearFilters(for: .issues) },
                onRetry: refresh
            )
        case .pipelines:
            GitLabPipelinesView(
                mode: mode,
                items: viewModel.visiblePipelines.map(GitLabWorkItemPresentation.init(pipeline:)),
                loadState: viewModel.loadState(for: .pipelines),
                filter: viewModel.filter(for: .pipelines),
                warning: viewModel.pipelineWarning,
                selectedItemID: viewModel.selection.item,
                onSelect: viewModel.select,
                onStatusChange: { statuses in
                    var filter = viewModel.filter(for: .pipelines)
                    filter.statuses = statuses
                    viewModel.setFilter(filter, for: .pipelines)
                },
                onClearFilters: { viewModel.clearFilters(for: .pipelines) },
                onRetry: refresh
            )
        }
    }

    private var searchText: Binding<String> {
        Binding(
            get: { viewModel.searchText },
            set: { viewModel.searchText = $0 }
        )
    }

    private var selectedSection: Binding<GitLabWorkspaceSection> {
        Binding(
            get: { viewModel.selectedSection },
            set: { viewModel.selectedSection = $0 }
        )
    }

    private func refresh() {
        Task { await viewModel.refresh() }
    }
}

#Preview {
    NavigationStack {
        GitLabDashboardView(viewModel: GitLabDashboardViewModel())
    }
}
