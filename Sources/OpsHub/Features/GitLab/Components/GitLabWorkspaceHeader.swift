import SwiftUI

struct GitLabWorkspaceHeader: View {
    let mode: GitLabWorkspaceLayoutMode
    let projects: [GitLabProjectSummary]
    @Binding var selectedScope: GitLabProjectScope
    @Binding var searchText: String
    let isRefreshing: Bool
    let hasStaleData: Bool
    let lastUpdated: Date?
    let onRefresh: () -> Void

    var body: some View {
        Group {
            if mode == .narrow {
                VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
                    titleBlock
                    controls
                }
            } else {
                HStack(alignment: .top, spacing: GitLabDesignTokens.Spacing.large) {
                    titleBlock
                    Spacer(minLength: GitLabDesignTokens.Spacing.large)
                    controls
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xSmall) {
            Text("GitLab")
                .font(.largeTitle.bold())

            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                Text(selectedScope.title)

                Text("•")
                    .accessibilityHidden(true)

                Label(lastUpdatedText, systemImage: "clock")

                if hasStaleData {
                    Label("Some data is stale", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            TextField("Search GitLab", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: mode == .narrow ? 180 : 220, maxWidth: 300)
                .accessibilityLabel("Search GitLab work items")

            Picker("Project scope", selection: $selectedScope) {
                Text("All projects")
                    .tag(GitLabProjectScope.allProjects)

                ForEach(projects) { project in
                    Text(project.nameWithNamespace)
                        .tag(GitLabProjectScope.project(project))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 240)
            .accessibilityLabel("Project scope")

            Button(action: onRefresh) {
                if isRefreshing {
                    LoadingSpinnerView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "Refreshing GitLab" : "Refresh GitLab")
        }
        .controlSize(.regular)
    }

    private var lastUpdatedText: String {
        guard let lastUpdated else {
            return "Never updated"
        }
        return "Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }
}

#Preview("Header — wide") {
    GitLabWorkspaceHeader(
        mode: .wide,
        projects: [GitLabProjectSummary(id: 1, nameWithNamespace: "ops/opshub", webURL: nil)],
        selectedScope: .constant(.allProjects),
        searchText: .constant(""),
        isRefreshing: false,
        hasStaleData: false,
        lastUpdated: .now,
        onRefresh: {}
    )
    .padding(32)
    .frame(width: 1_180)
}

#Preview("Header — narrow") {
    GitLabWorkspaceHeader(
        mode: .narrow,
        projects: [],
        selectedScope: .constant(.allProjects),
        searchText: .constant(""),
        isRefreshing: false,
        hasStaleData: true,
        lastUpdated: nil,
        onRefresh: {}
    )
    .padding(16)
    .frame(width: 720)
}
