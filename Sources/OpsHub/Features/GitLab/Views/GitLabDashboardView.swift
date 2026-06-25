import SwiftUI

/// Main GitLab dashboard screen with summary metrics and work item lists.
struct GitLabDashboardView: View {
    @StateObject private var viewModel: GitLabDashboardViewModel
    @State private var selectedMergeRequestID: GitLabMergeRequest.ID?
    @State private var selectedIssueID: GitLabIssue.ID?

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)
    ]

    init(settingsStore: any GitLabSettingsStoring = GitLabSettingsStore()) {
        _viewModel = StateObject(
            wrappedValue: GitLabDashboardViewModel(
                service: GitLabService(settingsStore: settingsStore),
                gitLabBaseURL: URL(string: settingsStore.load().gitLabURL)
            )
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .navigationTitle("GitLab Dashboard")
        .toolbar {
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
        }
        .task {
            await viewModel.loadDashboard()
        }
        .animation(.smooth(duration: 0.25), value: viewModel.isLoading)
        .animation(.smooth(duration: 0.25), value: viewModel.mergeRequests)
        .animation(.smooth(duration: 0.25), value: viewModel.issues)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GitLab Dashboard")
                    .font(.largeTitle.bold())

                HStack(spacing: 8) {
                    Text("Overview of your GitLab work")

                    Text("-")

                    Label(lastUpdatedText, systemImage: "clock")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.isLoading {
                    LoadingSpinnerView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(viewModel.isLoading)
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
            statisticGrid
            MergeRequestsCard(
                mergeRequests: viewModel.mergeRequests,
                isLoading: viewModel.isLoading,
                selectedMergeRequestID: $selectedMergeRequestID
            )
            IssuesCard(
                issues: viewModel.issues,
                isLoading: viewModel.isLoading,
                selectedIssueID: $selectedIssueID
            )
        }
    }

    private var statisticGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(viewModel.statistics) { statistic in
                StatisticCard(
                    icon: statistic.icon,
                    title: statistic.title,
                    number: statistic.number,
                    subtitle: statistic.subtitle,
                    webURL: statistic.webURL
                )
            }
        }
    }

    private var lastUpdatedText: String {
        guard let lastUpdated = viewModel.lastUpdated else {
            return "Last updated: Never"
        }

        return "Last updated: \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }
}

#Preview {
    NavigationStack {
        GitLabDashboardView()
    }
}
