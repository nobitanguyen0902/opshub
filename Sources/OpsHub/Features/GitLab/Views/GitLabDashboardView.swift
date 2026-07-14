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
                    sectionContent
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
    private var content: some View {
        if viewModel.isLoading && viewModel.isEmpty {
            GitLabLoadingState()
        } else if viewModel.isEmpty {
            EmptyStateView(
                systemImage: "tray",
                title: "No GitLab activity",
                message: "Refresh the dashboard after connecting projects or assigning work."
            )
            .frame(maxWidth: .infinity, minHeight: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
        } else {
            MergeRequestsCard(
                mergeRequests: viewModel.mergeRequests,
                isLoading: viewModel.isLoading,
                selectedMergeRequestID: selectedMergeRequestID
            )
            MergeReviewsCard(
                mergeReviews: viewModel.mergeReviews,
                isLoading: viewModel.isLoading,
                selectedMergeReviewID: selectedMergeReviewID
            )
            IssuesCard(
                issues: viewModel.issues,
                isLoading: viewModel.isLoading,
                selectedIssueID: selectedIssueID
            )
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedSection {
        case .overview:
            content
        case .mergeRequests:
            MergeRequestsCard(
                mergeRequests: viewModel.visibleMergeRequests,
                isLoading: viewModel.isLoading,
                selectedMergeRequestID: selectedMergeRequestID
            )
        case .reviews:
            MergeReviewsCard(
                mergeReviews: viewModel.visibleMergeReviews,
                isLoading: viewModel.isLoading,
                selectedMergeReviewID: selectedMergeReviewID
            )
        case .issues:
            IssuesCard(
                issues: viewModel.issues,
                isLoading: viewModel.isLoading,
                selectedIssueID: selectedIssueID
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

    private var selectedMergeRequestID: Binding<GitLabMergeRequest.ID?> {
        Binding(
            get: {
                guard case let .mergeRequest(id) = viewModel.selection.item else { return nil }
                return id
            },
            set: { id in
                viewModel.select(id.map(GitLabWorkspaceItemID.mergeRequest))
            }
        )
    }

    private var selectedMergeReviewID: Binding<GitLabMergeRequest.ID?> {
        Binding(
            get: {
                guard case let .review(id) = viewModel.selection.item else { return nil }
                return id
            },
            set: { id in
                viewModel.select(id.map(GitLabWorkspaceItemID.review))
            }
        )
    }

    private var selectedIssueID: Binding<GitLabIssue.ID?> {
        Binding(
            get: {
                guard case let .issue(id) = viewModel.selection.item else { return nil }
                return id
            },
            set: { id in
                viewModel.select(id.map(GitLabWorkspaceItemID.issue))
            }
        )
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
