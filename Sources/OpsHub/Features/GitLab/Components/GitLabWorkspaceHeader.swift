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
        OpsHubFeatureHeader(
            eyebrow: "OPSHUB / GITLAB",
            title: "Workspace",
            metadata: metadata
        ) {
            controls
        }
    }

    private var metadata: String {
        var parts = [
            "scope=\(selectedScope.title)",
            "updated=\(lastUpdatedText)"
        ]
        if hasStaleData {
            parts.append("status=stale")
        }
        return parts.joined(separator: " · ")
    }

    private var controls: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            TextField("Search GitLab", text: $searchText)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .opsHubTerminalInput()
                .frame(minWidth: mode == .narrow ? 180 : 220, maxWidth: 300)
                .accessibilityLabel("Search GitLab work items")

            Menu {
                Button {
                    selectedScope = .allProjects
                } label: {
                    if selectedScope == .allProjects {
                        Label("All projects", systemImage: "checkmark")
                    } else {
                        Text("All projects")
                    }
                }

                Divider()
                ForEach(projects) { project in
                    let scope = GitLabProjectScope.project(project)
                    Button {
                        selectedScope = scope
                    } label: {
                        if selectedScope == scope {
                            Label(project.nameWithNamespace, systemImage: "checkmark")
                        } else {
                            Text(project.nameWithNamespace)
                        }
                    }
                }
            } label: {
                HStack(spacing: GitLabDesignTokens.Spacing.medium) {
                    Image(systemName: "folder")
                        .foregroundStyle(GitLabDesignTokens.terminalAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SELECTED PROJECT")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text(selectedScope.title)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundStyle(GitLabDesignTokens.terminalAccent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: GitLabDesignTokens.Spacing.small)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 240, maxWidth: 240, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
                .gitLabTerminalControl()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("Project scope")
            .accessibilityValue(selectedScope.title)

            Button(action: onRefresh) {
                if isRefreshing {
                    LoadingSpinnerView()
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.plain)
            .gitLabTerminalControl()
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "Refreshing GitLab" : "Refresh GitLab")
        }
        .controlSize(.regular)
    }

    private var lastUpdatedText: String {
        guard let lastUpdated else {
            return "never"
        }
        return lastUpdated.formatted(date: .omitted, time: .shortened)
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
