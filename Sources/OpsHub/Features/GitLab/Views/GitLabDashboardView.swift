import SwiftUI

/// Main GitLab dashboard screen with summary metrics and work item lists.
struct GitLabDashboardView: View {
    @StateObject private var viewModel: GitLabDashboardViewModel

    init(settingsStore: any GitLabSettingsStoring = GitLabSettingsStore()) {
        _viewModel = StateObject(
            wrappedValue: GitLabDashboardViewModel(
                service: GitLabService(settingsStore: settingsStore),
                gitLabBaseURL: URL(string: settingsStore.load().gitLabURL)
            )
        )
    }

    var body: some View {
        GitLabAdaptiveLayout { mode in
            ScrollView {
                VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xLarge) {
                    header(mode: mode)
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
                .padding(mode.pagePadding)
            }
        }
        .navigationTitle("GitLab")
        .task {
            await viewModel.loadDashboard()
        }
        .animation(.smooth(duration: 0.25), value: viewModel.isLoading)
        .animation(.smooth(duration: 0.25), value: viewModel.mergeRequests)
        .animation(.smooth(duration: 0.25), value: viewModel.mergeReviews)
        .animation(.smooth(duration: 0.25), value: viewModel.issues)
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
                .font(.callout)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                notifications: viewModel.notificationPreview,
                selectedItemID: viewModel.selection.item,
                loadState: viewModel.isLoading && viewModel.isEmpty ? .initialLoading : .loaded,
                onSelect: viewModel.select,
                onShowSection: { viewModel.selectedSection = $0 }
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
                onClearFilters: { viewModel.clearFilters(for: .mergeRequests) }
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
                onClearFilters: { viewModel.clearFilters(for: .reviews) }
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
                onClearFilters: { viewModel.clearFilters(for: .issues) }
            )
        case .pipelines:
            EmptyStateView(
                systemImage: "play.circle",
                title: "Pipelines",
                message: "Pipeline details will appear in this section."
            )
            .frame(maxWidth: .infinity, minHeight: 240)
            .gitLabSurface()
        case .notifications:
            EmptyStateView(
                systemImage: "bell",
                title: "Notifications",
                message: "GitLab notifications will appear in this section."
            )
            .frame(maxWidth: .infinity, minHeight: 240)
            .gitLabSurface()
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
}

#Preview {
    NavigationStack {
        GitLabDashboardView()
    }
}
