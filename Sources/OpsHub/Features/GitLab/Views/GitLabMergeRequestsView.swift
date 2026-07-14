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

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            statusMenu
            GitLabWorkItemList(
                title: "Merge requests",
                items: items,
                mode: mode,
                loadState: loadState,
                isFiltered: filter.isEmpty == false,
                selectedItemID: selectedItemID,
                emptyTitle: "No merge requests",
                emptyMessage: "Your merge requests will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: onClearFilters
            )
        }
    }

    private var statusMenu: some View {
        Menu {
            Button("All statuses") { onStatusChange([]) }
            Divider()
            ForEach(statuses, id: \.self) { status in
                Button(status.rawValue) { onStatusChange([status.rawValue]) }
            }
        } label: {
            Label(filter.statuses.first ?? "All statuses", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.bordered)
        .accessibilityLabel("Filter merge requests by status")
    }

    private var statuses: [GitLabMergeRequestStatus] {
        [.opened, .reviewing, .approved, .draft]
    }
}
