import SwiftUI

struct GitLabOverviewView: View {
    let mode: GitLabWorkspaceLayoutMode
    let actionQueue: [GitLabWorkItemPresentation]
    let mergeRequests: [GitLabWorkItemPresentation]
    let pipelines: [GitLabWorkItemPresentation]
    let notifications: [GitLabWorkItemPresentation]
    let selectedItemID: GitLabWorkspaceItemID?
    let loadState: GitLabSectionLoadState
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onShowSection: (GitLabWorkspaceSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xLarge) {
            GitLabWorkItemList(
                title: "Action queue",
                items: actionQueue,
                mode: mode,
                loadState: loadState,
                isFiltered: false,
                selectedItemID: selectedItemID,
                emptyTitle: "You're all caught up",
                emptyMessage: "New reviews, assignments, failures, and mentions will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: nil
            )

            previewGrid
        }
    }

    @ViewBuilder
    private var previewGrid: some View {
        if mode == .wide {
            HStack(alignment: .top, spacing: GitLabDesignTokens.Spacing.large) {
                preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
                preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
                preview(title: "Recent notifications", items: notifications, section: .notifications)
            }
        } else {
            VStack(spacing: GitLabDesignTokens.Spacing.large) {
                preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
                preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
                preview(title: "Recent notifications", items: notifications, section: .notifications)
            }
        }
    }

    private func preview(
        title: String,
        items: [GitLabWorkItemPresentation],
        section: GitLabWorkspaceSection
    ) -> some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.small) {
            Button("View all \(title.lowercased())") {
                onShowSection(section)
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)

            GitLabWorkItemList(
                title: title,
                items: items,
                mode: mode,
                loadState: .loaded,
                isFiltered: false,
                selectedItemID: selectedItemID,
                emptyTitle: "No recent items",
                emptyMessage: "Activity will appear here.",
                onSelect: onSelect,
                onQuickAction: nil,
                onClearFilters: nil
            )
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
