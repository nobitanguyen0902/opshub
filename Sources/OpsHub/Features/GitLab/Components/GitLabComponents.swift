import SwiftUI

/// Summary metric card used by the GitLab dashboard.
struct StatisticCard: View {
    @Environment(\.openURL) private var openURL

    let icon: String
    let title: String
    let number: String
    let subtitle: String
    let webURL: URL?
    @State private var isHovering = false

    var body: some View {
        Button(action: openDashboard) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.secondary)

                    Text(number)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    private func openDashboard() {
        if let webURL {
            openURL(webURL)
        }
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
    @State private var selectedTab = GitLabIssueTab.assignedToMe

    var body: some View {
        GitLabListCard(
            title: "Issues",
            count: filteredIssues.count,
            isLoading: isLoading,
            emptyTitle: "No issues",
            emptyMessage: "Issues matching this tab will appear here after refresh.",
            showsContentWhenEmpty: true
        ) {
            VStack(spacing: 0) {
                Picker("Issue filter", selection: $selectedTab) {
                    ForEach(GitLabIssueTab.allCases) { tab in
                        Text(tab.rawValue)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)

                if filteredIssues.isEmpty {
                    EmptyStateView(
                        systemImage: "tray",
                        title: "No issues",
                        message: "Issues matching this tab will appear here after refresh."
                    )
                    .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    GitLabSelectableList(items: filteredIssues) { issue in
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
    }

    private var filteredIssues: [GitLabIssue] {
        issues.filter(selectedTab.includes)
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
                            LoadingSpinnerView()
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
    let showsContentWhenEmpty: Bool
    let content: () -> Content
    @State private var isHovering = false

    init(
        title: String,
        count: Int,
        isLoading: Bool,
        emptyTitle: String,
        emptyMessage: String,
        showsContentWhenEmpty: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.count = count
        self.isLoading = isLoading
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.showsContentWhenEmpty = showsContentWhenEmpty
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text("\(count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tertiary, in: Capsule())

                Spacer()

                if isLoading {
                    LoadingSpinnerView()
                } else {
                    Button("View All") {}
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .padding(16)

            if count == 0 && showsContentWhenEmpty == false {
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
    @Environment(\.openURL) private var openURL

    let reference: String
    let title: String
    let project: String
    let avatarURL: URL?
    let avatarAccessibilityLabel: String?
    let showsAvatar: Bool
    let showsFullContent: Bool
    let labels: [GitLabLabel]
    let updatedTime: String
    let webURL: URL?
    let isSelected: Bool
    let onSelect: () -> Void
    let badge: () -> Badge

    init(
        reference: String,
        title: String,
        project: String,
        avatarURL: URL? = nil,
        avatarAccessibilityLabel: String? = nil,
        showsAvatar: Bool = false,
        showsFullContent: Bool = false,
        labels: [GitLabLabel] = [],
        updatedTime: String,
        webURL: URL?,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        @ViewBuilder badge: @escaping () -> Badge
    ) {
        self.reference = reference
        self.title = title
        self.project = project
        self.avatarURL = avatarURL
        self.avatarAccessibilityLabel = avatarAccessibilityLabel
        self.showsAvatar = showsAvatar
        self.showsFullContent = showsFullContent
        self.labels = labels
        self.updatedTime = updatedTime
        self.webURL = webURL
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.badge = badge
    }

    var body: some View {
        Button(action: selectAndOpen) {
            HStack(alignment: .center, spacing: 14) {
                if showsAvatar {
                    GitLabAvatar(
                        url: avatarURL,
                        accessibilityLabel: avatarAccessibilityLabel
                    )
                }

                Text(reference)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(showsFullContent ? nil : 1)
                        .fixedSize(horizontal: false, vertical: showsFullContent)

                    Text(project)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(showsFullContent ? nil : 1)
                        .fixedSize(horizontal: false, vertical: showsFullContent)

                    if labels.isEmpty == false {
                        GitLabFlowLayout(spacing: 6) {
                            ForEach(labels, id: \.self) { label in
                                GitLabLabelBadge(label: label)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                badge()

                Text(updatedTime)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 78, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
            .gitLabRowHoverBackground(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func selectAndOpen() {
        onSelect()

        if let webURL {
            openURL(webURL)
        }
    }

}

private struct GitLabFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )

        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }

            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }

        let width = maxWidth.isFinite ? maxWidth : max(x - spacing, 0)
        return (CGSize(width: width, height: y + lineHeight), points)
    }
}

private struct GitLabAvatar: View {
    let url: URL?
    let accessibilityLabel: String?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay {
            Circle()
                .strokeBorder(Color.primary.opacity(0.1))
        }
        .accessibilityLabel(accessibilityLabel ?? "GitLab user avatar")
    }
}

private struct GitLabLabelBadge: View {
    let label: GitLabLabel

    var body: some View {
        Text(label.name)
            .font(.caption.weight(.medium))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
    }

    private var backgroundColor: Color {
        Color(gitLabHex: label.color) ?? Color.accentColor.opacity(0.1)
    }

    private var foregroundColor: Color {
        Color(gitLabHex: label.textColor) ?? Color.accentColor
    }
}

private extension Color {
    init?(gitLabHex value: String?) {
        guard let value else { return nil }
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let number = UInt64(hex, radix: 16) else { return nil }

        self.init(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
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
            avatarURL: mergeRequest.authorAvatarURL,
            avatarAccessibilityLabel: mergeRequest.authorName,
            showsAvatar: true,
            updatedTime: mergeRequest.updatedTime,
            webURL: mergeRequest.webURL,
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
            avatarURL: issue.assigneeAvatarURL,
            avatarAccessibilityLabel: issue.assigneeName,
            showsAvatar: true,
            showsFullContent: true,
            labels: issue.labelDetails,
            updatedTime: issue.updatedTime,
            webURL: issue.webURL,
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
            .font(.subheadline.weight(.semibold))
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
            subtitle: "4 waiting for review",
            webURL: URL(string: "https://gitlab.example.com/dashboard/merge_requests")
        )

        MergeRequestsCard(
            mergeRequests: [],
            isLoading: false,
            selectedMergeRequestID: .constant(nil)
        )

        IssuesCard(
            issues: [],
            isLoading: false,
            selectedIssueID: .constant(nil)
        )
    }
    .padding()
}
