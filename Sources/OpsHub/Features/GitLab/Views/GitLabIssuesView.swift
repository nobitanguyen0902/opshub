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

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            ScrollView(.horizontal, showsIndicators: false) {
                Picker("Issue workflow", selection: $selectedTab) {
                    ForEach(GitLabIssueTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(minWidth: 560)
            }

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
                onClearFilters: onClearFilters
            )
        }
    }
}
