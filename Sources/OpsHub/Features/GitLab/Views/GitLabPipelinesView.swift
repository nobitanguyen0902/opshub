import SwiftUI

struct GitLabPipelinesView: View {
    let mode: GitLabWorkspaceLayoutMode
    let items: [GitLabWorkItemPresentation]
    let loadState: GitLabSectionLoadState
    let filter: GitLabWorkspaceFilter
    let warning: String?
    let selectedItemID: GitLabWorkspaceItemID?
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onStatusChange: (Set<String>) -> Void
    let onClearFilters: () -> Void
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Partial pipeline results. \(warning)")
            }

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

            GitLabWorkItemList(
                title: "Pipelines",
                items: items,
                mode: mode,
                loadState: loadState,
                isFiltered: filter.isEmpty == false,
                selectedItemID: selectedItemID,
                emptyTitle: "No pipelines",
                emptyMessage: "Recent project pipelines will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: onClearFilters,
                onRetry: onRetry
            )
        }
    }

    private var statuses: [GitLabPipelineStatus] {
        [.running, .passed, .failed, .canceled]
    }
}
