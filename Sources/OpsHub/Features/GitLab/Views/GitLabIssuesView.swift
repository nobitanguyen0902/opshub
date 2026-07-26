import SwiftUI

struct GitLabIssuesView: View {
    let mode: GitLabWorkspaceLayoutMode
    let items: [GitLabWorkItemPresentation]
    let loadState: GitLabSectionLoadState
    let filter: GitLabWorkspaceFilter
    let selectedItemID: GitLabWorkspaceItemID?
    @Binding var selectedTab: GitLabIssueTab
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onClearFilters: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
                    ForEach(GitLabIssueTab.allCases) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            Text(tab.rawValue.uppercased())
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .foregroundStyle(
                                    selectedTab == tab
                                        ? GitLabDesignTokens.terminalAccent
                                        : Color.primary.opacity(0.68)
                                )
                                .padding(.horizontal, GitLabDesignTokens.Spacing.medium)
                                .frame(minHeight: 34)
                                .background(
                                    selectedTab == tab
                                        ? GitLabDesignTokens.surfaceSelected
                                        : GitLabDesignTokens.surfacePrimary
                                )
                                .overlay(alignment: .bottom) {
                                    Rectangle()
                                        .fill(GitLabDesignTokens.terminalAccent)
                                        .frame(height: 2)
                                        .opacity(selectedTab == tab ? 1 : 0)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
                    }
                }
                .padding(GitLabDesignTokens.Spacing.xSmall)
                .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control)
                .frame(minWidth: 560)
            }
            .accessibilityLabel("Issue workflow")

            GitLabWorkItemList(
                title: "Issues",
                items: items,
                mode: mode,
                loadState: loadState,
                isFiltered: filter.isEmpty == false,
                selectedItemID: selectedItemID,
                emptyTitle: "No issues in this workflow",
                emptyMessage: "Issues matching the selected workflow will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: onClearFilters,
                onRetry: onRetry
            )
        }
    }
}
