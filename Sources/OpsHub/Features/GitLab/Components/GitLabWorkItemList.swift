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
    let onRetry: (() -> Void)?
    let onViewAll: (() -> Void)?

    init(
        title: String,
        items: [GitLabWorkItemPresentation],
        mode: GitLabWorkspaceLayoutMode,
        loadState: GitLabSectionLoadState,
        isFiltered: Bool,
        selectedItemID: GitLabWorkspaceItemID?,
        emptyTitle: String,
        emptyMessage: String,
        onSelect: @escaping (GitLabWorkspaceItemID) -> Void,
        onQuickAction: ((GitLabWorkspaceItemID) -> Void)?,
        onClearFilters: (() -> Void)?,
        onRetry: (() -> Void)?,
        onViewAll: (() -> Void)? = nil
    ) {
        self.title = title
        self.items = items
        self.mode = mode
        self.loadState = loadState
        self.isFiltered = isFiltered
        self.selectedItemID = selectedItemID
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.onSelect = onSelect
        self.onQuickAction = onQuickAction
        self.onClearFilters = onClearFilters
        self.onRetry = onRetry
        self.onViewAll = onViewAll
    }

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
            Text("::")
                .foregroundStyle(GitLabDesignTokens.terminalAccent)

            Text(title.uppercased())
                .foregroundStyle(.primary)

            Text("[\(items.count)]")
                .monospacedDigit()
                .foregroundStyle(.secondary)

            Spacer()

            if loadState == .refreshing {
                LoadingSpinnerView()
                    .accessibilityLabel("Refreshing \(title)")
            }

            if let onViewAll {
                Button("VIEW ALL →", action: onViewAll)
                    .buttonStyle(.plain)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(GitLabDesignTokens.terminalAccent)
                    .accessibilityLabel("View all \(title.lowercased())")
            }
        }
        .font(.system(.callout, design: .monospaced).weight(.semibold))
        .padding(GitLabDesignTokens.Spacing.large)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(GitLabDesignTokens.borderSubtle)
                .frame(height: GitLabDesignTokens.borderWidth)
        }
    }

    @ViewBuilder
    private var content: some View {
        if loadState == .initialLoading && items.isEmpty {
            ProgressView("Loading \(title)...")
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if case let .failed(message) = loadState, items.isEmpty {
            VStack(spacing: GitLabDesignTokens.Spacing.medium) {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to load \(title)",
                    message: message
                )
                if let onRetry {
                    Button("Retry", action: onRetry)
                        .buttonStyle(.borderedProminent)
                }
            }
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
        onClearFilters: nil,
        onRetry: nil
    )
    .padding()
}
