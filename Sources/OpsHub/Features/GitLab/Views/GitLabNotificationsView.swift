import SwiftUI

struct GitLabNotificationsView: View {
    let mode: GitLabWorkspaceLayoutMode
    let items: [GitLabWorkItemPresentation]
    let loadState: GitLabSectionLoadState
    let filter: GitLabWorkspaceFilter
    let selectedItemID: GitLabWorkspaceItemID?
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onClearFilters: () -> Void

    var body: some View {
        GitLabWorkItemList(
            title: "Pending notifications",
            items: items,
            mode: mode,
            loadState: loadState,
            isFiltered: filter.isEmpty == false,
            selectedItemID: selectedItemID,
            emptyTitle: "No pending notifications",
            emptyMessage: "You're caught up with GitLab todos.",
            onSelect: onSelect,
            onQuickAction: nil,
            onClearFilters: onClearFilters
        )
    }
}
