import SwiftUI

struct GitLabMergeRequestSection: View {
    let title: String
    let filterAccessibilityLabel: String
    let emptyTitle: String
    let emptyMessage: String
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
            .accessibilityLabel(filterAccessibilityLabel)

            GitLabWorkItemList(
                title: title,
                items: items,
                mode: mode,
                loadState: loadState,
                isFiltered: filter.isEmpty == false,
                selectedItemID: selectedItemID,
                emptyTitle: emptyTitle,
                emptyMessage: emptyMessage,
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: onClearFilters,
                onRetry: onRetry
            )
        }
    }

    private var statuses: [GitLabMergeRequestStatus] {
        [.opened, .reviewing, .approved, .draft]
    }
}
