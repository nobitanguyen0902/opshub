import SwiftUI

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
            ForEach(mergeRequests) { mergeRequest in
                MergeRequestRow(
                    mergeRequest: mergeRequest,
                    isSelected: selectedMergeRequestID == mergeRequest.id
                ) {
                    selectedMergeRequestID = mergeRequest.id
                }

                if mergeRequest.id != mergeRequests.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }
}

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
            ForEach(issues) { issue in
                IssueRow(
                    issue: issue,
                    isSelected: selectedIssueID == issue.id
                ) {
                    selectedIssueID = issue.id
                }

                if issue.id != issues.last?.id {
                    Divider()
                        .padding(.leading, 16)
                }
            }
        }
    }
}

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

private struct MergeRequestRow: View {
    let mergeRequest: GitLabMergeRequest
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Text("!\(mergeRequest.id)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mergeRequest.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(mergeRequest.project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                MergeRequestStatusBadge(status: mergeRequest.status)

                Text(mergeRequest.updatedTime)
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

private struct IssueRow: View {
    let issue: GitLabIssue
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 14) {
                Text("#\(issue.id)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(issue.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(issue.project)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                IssuePriorityBadge(priority: issue.priority)

                Text(issue.updatedTime)
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

private struct MergeRequestStatusBadge: View {
    let status: GitLabMergeRequestStatus

    var body: some View {
        Text(status.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
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

    private var backgroundColor: Color {
        foregroundColor.opacity(0.14)
    }
}

private struct IssuePriorityBadge: View {
    let priority: GitLabIssuePriority

    var body: some View {
        Text(priority.rawValue)
            .font(.caption.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(backgroundColor, in: Capsule())
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

    private var backgroundColor: Color {
        foregroundColor.opacity(0.14)
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
