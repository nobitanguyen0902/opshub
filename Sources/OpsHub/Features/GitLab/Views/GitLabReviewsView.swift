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

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
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
            .accessibilityLabel("Filter reviews by status")

            GitLabWorkItemList(
                title: "Reviews",
                items: items,
                mode: mode,
                loadState: loadState,
                isFiltered: filter.isEmpty == false,
                selectedItemID: selectedItemID,
                emptyTitle: "No reviews waiting",
                emptyMessage: "Merge requests awaiting your review will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: onClearFilters
            )
        }
    }

    private var statuses: [GitLabMergeRequestStatus] {
        [.opened, .reviewing, .approved, .draft]
    }
}
