import SwiftUI

/// Summary metric card used by the GitLab dashboard.
struct StatisticCard: View {
    let icon: String
    let title: String
    let number: String
    let subtitle: String
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)

                Text(number)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.05), radius: isHovering ? 14 : 6, y: isHovering ? 8 : 3)
        .scaleEffect(isHovering ? 1.015 : 1)
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.18), value: isHovering)
    }
}

/// List card for merge requests on the GitLab dashboard.
struct MergeRequestsCard: View {
    let mergeRequests: [GitLabMergeRequest]
    let isLoading: Bool
    @Binding var selectedMergeRequestID: GitLabMergeRequest.ID?

    var body: some View {
        GitLabListCard(
            title: "Merge Requests",
            count: mergeRequests.count,
            isLoading: isLoading,
            emptyTitle: "No merge requests",
            emptyMessage: "Assigned merge requests will appear here after refresh."
        ) {
            GitLabSelectableList(items: mergeRequests) { mergeRequest in
                MergeRequestRow(
                    mergeRequest: mergeRequest,
                    isSelected: selectedMergeRequestID == mergeRequest.id
                ) {
                    selectedMergeRequestID = mergeRequest.id
                }
            }
        }
    }
}

/// List card for issues on the GitLab dashboard.
struct IssuesCard: View {
    let issues: [GitLabIssue]
    let isLoading: Bool
    @Binding var selectedIssueID: GitLabIssue.ID?

    var body: some View {
        GitLabListCard(
            title: "Issues",
            count: issues.count,
            isLoading: isLoading,
            emptyTitle: "No issues",
            emptyMessage: "Assigned or mentioned issues will appear here after refresh."
        ) {
            GitLabSelectableList(items: issues) { issue in
                IssueRow(
                    issue: issue,
                    isSelected: selectedIssueID == issue.id
                ) {
                    selectedIssueID = issue.id
                }
            }
        }
    }
}

/// Loading placeholder shown while the GitLab dashboard fetches its first data.
struct GitLabLoadingState: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView("Loading GitLab dashboard...")
                .controlSize(.large)

            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(height: 150)
                        .overlay {
                            ProgressView()
                                .controlSize(.small)
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

private struct GitLabListCard<Content: View>: View {
    let title: String
    let count: Int
    let isLoading: Bool
    let emptyTitle: String
    let emptyMessage: String
    let content: () -> Content
    @State private var isHovering = false

    init(
        title: String,
        count: Int,
        isLoading: Bool,
        emptyTitle: String,
        emptyMessage: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.isLoading = isLoading
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.headline)

                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tertiary, in: Capsule())

                Spacer()

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("View All") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(16)

            if count == 0 {
                EmptyStateView(
                    systemImage: "tray",
                    title: emptyTitle,
                    message: emptyMessage
                )
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    content()
                        .redacted(reason: isLoading ? .placeholder : [])
                        .allowsHitTesting(!isLoading)
                        .opacity(isLoading ? 0.72 : 1)
                        .animation(.smooth(duration: 0.2), value: isLoading)
                }
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.05), radius: isHovering ? 16 : 6, y: isHovering ? 8 : 3)
        .onHover { isHovering = $0 }
        .animation(.smooth(duration: 0.18), value: isHovering)
    }
}

private struct RowHoverBackground: ViewModifier {
    let isSelected: Bool
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
            }
            .onHover { isHovering = $0 }
            .animation(.smooth(duration: 0.16), value: isHovering)
            .animation(.smooth(duration: 0.16), value: isSelected)
    }

    private var backgroundColor: Color {
        if isSelected {
            Color.accentColor.opacity(0.14)
        } else if isHovering {
            Color.primary.opacity(0.06)
        } else {
            Color.clear
        }
    }
}

private extension View {
    func gitLabRowHoverBackground(isSelected: Bool) -> some View {
        modifier(RowHoverBackground(isSelected: isSelected))
    }
}

private struct GitLabSelectableList<Item: Identifiable, Row: View>: View where Item.ID: Equatable {
    let items: [Item]
    let row: (Item) -> Row

    init(
        items: [Item],
        @ViewBuilder row: @escaping (Item) -> Row
    ) {
        self.items = items
        self.row = row
    }

    var body: some View {
        ForEach(items) { item in
            row(item)

            if item.id != items.last?.id {
                Divider()
                    .padding(.leading, 16)
            }
        }
    }
}

private struct GitLabSelectableRow<Badge: View>: View {
    let reference: String
    let title: String
    let project: String
    let updatedTime: String
    let isSelected: Bool
    let onSelect: () -> Void
    let badge: () -> Badge

    init(
        reference: String,
        title: String,
        project: String,
        updatedTime: String,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder badge: @escaping () -> Badge
    ) {
        self.reference = reference
        self.title = title
        self.project = project
        self.updatedTime = updatedTime
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.badge = badge
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Text(reference)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                badge()

                Text(updatedTime)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .gitLabRowHoverBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

private struct MergeRequestRow: View {
    let mergeRequest: GitLabMergeRequest
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        GitLabSelectableRow(
            reference: "!\(mergeRequest.id)",
            title: mergeRequest.title,
            project: mergeRequest.project,
            updatedTime: mergeRequest.updatedTime,
            isSelected: isSelected,
            onSelect: onSelect
        ) {
            MergeRequestStatusBadge(status: mergeRequest.status)
        }
    }
}

private struct IssueRow: View {
    let issue: GitLabIssue
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        GitLabSelectableRow(
            reference: "#\(issue.id)",
            title: issue.title,
            project: issue.project,
            updatedTime: issue.updatedTime,
            isSelected: isSelected,
            onSelect: onSelect
        ) {
            IssuePriorityBadge(priority: issue.priority)
        }
    }
}

private struct MergeRequestStatusBadge: View {
    let status: GitLabMergeRequestStatus

    var body: some View {
        GitLabBadge(title: status.rawValue, foregroundColor: foregroundColor)
    }

    private var foregroundColor: Color {
        switch status {
        case .opened:
            .green
        case .reviewing:
            .orange
        case .approved:
            .blue
        case .draft:
            .secondary
        }
    }

}

private struct IssuePriorityBadge: View {
    let priority: GitLabIssuePriority

    var body: some View {
        GitLabBadge(title: priority.rawValue, foregroundColor: foregroundColor)
    }

    private var foregroundColor: Color {
        switch priority {
        case .urgent:
            .red
        case .high:
            .orange
        case .medium:
            .blue
        case .low:
            .secondary
        }
    }

}

private struct GitLabBadge: View {
    let title: String
    let foregroundColor: Color

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(foregroundColor.opacity(0.14), in: Capsule())
    }
}

#Preview {
    VStack {
        StatisticCard(
            icon: "arrow.triangle.merge",
            title: "Merge Requests",
            number: "12",
            subtitle: "4 waiting for review"
        )

        MergeRequestsCard(
            mergeRequests: GitLabMocks.mergeRequests,
            isLoading: false,
            selectedMergeRequestID: .constant(1842)
        )

        IssuesCard(
            issues: GitLabMocks.issues,
            isLoading: false,
            selectedIssueID: .constant(9281)
        )
    }
    .padding()
}
