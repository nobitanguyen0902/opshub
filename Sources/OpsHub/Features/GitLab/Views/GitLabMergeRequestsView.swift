import SwiftUI

struct GitLabMergeRequestsView: View {
    let mode: GitLabWorkspaceLayoutMode
    let items: [GitLabWorkItemPresentation]
    let loadState: GitLabSectionLoadState
    let filter: GitLabWorkspaceFilter
    let selectedItemID: GitLabWorkspaceItemID?
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onStatusChange: (Set<String>) -> Void
    let onClearFilters: () -> Void
    let onRetry: () -> Void

    var body: some View {
        GitLabMergeRequestSection(
            title: "Merge requests",
            filterAccessibilityLabel: "Filter merge requests by status",
            emptyTitle: "No merge requests",
            emptyMessage: "Your merge requests will appear here.",
            mode: mode,
            items: items,
            loadState: loadState,
            filter: filter,
            selectedItemID: selectedItemID,
            onSelect: onSelect,
            onStatusChange: onStatusChange,
            onClearFilters: onClearFilters,
            onRetry: onRetry
        )
    }
}
