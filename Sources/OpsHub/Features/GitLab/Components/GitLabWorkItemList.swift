import SwiftUI

struct GitLabWorkItemList: View {
    let title: String
    let items: [GitLabWorkItemPresentation]
    let mode: GitLabWorkspaceLayoutMode
    let loadState: GitLabSectionLoadState
    let isFiltered: Bool
    let selectedItemID: GitLabWorkspaceItemID?
    let emptyTitle: String
    let emptyMessage: String
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let onQuickAction: ((GitLabWorkspaceItemID) -> Void)?
    let onClearFilters: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if case let .stale(message) = loadState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, GitLabDesignTokens.Spacing.large)
                    .padding(.bottom, GitLabDesignTokens.Spacing.small)
            }

            content
        }
        .gitLabSurface()
    }

    private var header: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            Text(title)
                .font(.title3.weight(.semibold))

            Text("\(items.count)")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, GitLabDesignTokens.Spacing.small)
                .padding(.vertical, GitLabDesignTokens.Spacing.xSmall)
                .background(.tertiary, in: Capsule())

            Spacer()

            if loadState == .refreshing {
                LoadingSpinnerView()
                    .accessibilityLabel("Refreshing \(title)")
            }
        }
        .padding(GitLabDesignTokens.Spacing.large)
    }

    @ViewBuilder
    private var content: some View {
        if loadState == .initialLoading && items.isEmpty {
            ProgressView("Loading \(title)...")
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if case let .failed(message) = loadState, items.isEmpty {
            EmptyStateView(
                systemImage: "exclamationmark.triangle",
                title: "Unable to load \(title)",
                message: message
            )
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if items.isEmpty {
            VStack(spacing: GitLabDesignTokens.Spacing.medium) {
                EmptyStateView(
                    systemImage: "tray",
                    title: isFiltered ? "No matching items" : emptyTitle,
                    message: isFiltered ? "Change or clear the current filters." : emptyMessage
                )

                if isFiltered, let onClearFilters {
                    Button("Clear filters", action: onClearFilters)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    GitLabWorkItemRow(
                        item: item,
                        mode: mode,
                        isSelected: selectedItemID == item.id,
                        onSelect: onSelect,
                        quickAction: onQuickAction
                    )

                    if item.id != items.last?.id {
                        Divider()
                            .padding(.leading, GitLabDesignTokens.Spacing.large)
                    }
                }
            }
            .padding(.bottom, GitLabDesignTokens.Spacing.small)
        }
    }
}

#Preview("Work item list") {
    GitLabWorkItemList(
        title: "Reviews",
        items: [],
        mode: .wide,
        loadState: .loaded,
        isFiltered: false,
        selectedItemID: nil,
        emptyTitle: "No reviews",
        emptyMessage: "Merge requests awaiting review will appear here.",
        onSelect: { _ in },
        onQuickAction: nil,
        onClearFilters: nil
    )
    .padding()
}
