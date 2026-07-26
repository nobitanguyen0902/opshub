import SwiftUI

struct GitLabOverviewView: View {
    let mode: GitLabWorkspaceLayoutMode
    let actionQueue: [GitLabWorkItemPresentation]
    let mergeRequests: [GitLabWorkItemPresentation]
    let pipelines: [GitLabWorkItemPresentation]
    let selectedItemID: GitLabWorkspaceItemID?
    let loadState: GitLabSectionLoadState
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onShowSection: (GitLabWorkspaceSection) -> Void
    let onRetry: () -> Void

    var body: some View {
        Group {
            if mode == .wide {
                GitLabOverviewColumnsLayout(spacing: GitLabDesignTokens.Spacing.large) {
                    actionQueueSection
                    previewColumn
                }
            } else {
                VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xLarge) {
                    actionQueueSection
                    previewGrid
                }
            }
        }
    }

    private var actionQueueSection: some View {
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
            onClearFilters: nil,
            onRetry: onRetry
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.large) {
            preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
            preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var previewGrid: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.large) {
            preview(title: "My merge requests", items: mergeRequests, section: .mergeRequests)
            preview(title: "Recent pipelines", items: pipelines, section: .pipelines)
        }
    }

    private func preview(
        title: String,
        items: [GitLabWorkItemPresentation],
        section: GitLabWorkspaceSection
    ) -> some View {
        GitLabWorkItemList(
            title: title,
            items: items,
            mode: mode == .wide ? .narrow : mode,
            loadState: .loaded,
            isFiltered: false,
            selectedItemID: selectedItemID,
            emptyTitle: "No recent items",
            emptyMessage: "Activity will appear here.",
            onSelect: onSelect,
            onQuickAction: nil,
            onClearFilters: nil,
            onRetry: nil,
            onViewAll: { onShowSection(section) }
        )
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct GitLabOverviewColumnsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        guard subviews.count == 2 else {
            return .zero
        }

        guard let proposedWidth = proposal.width else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(
                width: sizes.reduce(0) { $0 + $1.width } + spacing,
                height: sizes.map(\.height).max() ?? 0
            )
        }

        let widths = columnWidths(for: proposedWidth)
        let heights = subviews.enumerated().map { index, subview in
            subview.sizeThatFits(
                ProposedViewSize(width: widths[index], height: proposal.height)
            ).height
        }

        return CGSize(width: proposedWidth, height: heights.max() ?? 0)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard subviews.count == 2 else {
            return
        }

        let widths = columnWidths(for: bounds.width)
        subviews[0].place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: widths[0], height: nil)
        )
        subviews[1].place(
            at: CGPoint(x: bounds.minX + widths[0] + spacing, y: bounds.minY),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: widths[1], height: nil)
        )
    }

    private func columnWidths(for totalWidth: CGFloat) -> [CGFloat] {
        let availableWidth = max(0, totalWidth - spacing)
        let actionQueueWidth = availableWidth * 5 / 8
        return [actionQueueWidth, availableWidth - actionQueueWidth]
    }
}
