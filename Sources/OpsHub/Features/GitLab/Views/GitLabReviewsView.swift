import SwiftUI

struct GitLabReviewsView: View {
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
            title: "Reviews",
            filterAccessibilityLabel: "Filter reviews by status",
            emptyTitle: "No reviews waiting",
            emptyMessage: "Merge requests awaiting your review will appear here.",
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
