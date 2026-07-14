import SwiftUI

struct GitLabWorkItemRow: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    let item: GitLabWorkItemPresentation
    let mode: GitLabWorkspaceLayoutMode
    let isSelected: Bool
    let onSelect: (GitLabWorkspaceItemID) -> Void
    let quickAction: ((GitLabWorkspaceItemID) -> Void)?

    var body: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            Button(action: selectAndOpen) {
                rowContent
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .accessibilityLabel(item.accessibilitySummary)
            .accessibilityHint(item.webURL == nil ? "Selects this item" : "Opens this item in GitLab")

            if let quickAction {
                Button {
                    quickAction(item.id)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("More actions for \(item.reference)")
            }
        }
        .padding(.horizontal, GitLabDesignTokens.Spacing.large)
        .padding(.vertical, GitLabDesignTokens.Spacing.medium)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: GitLabDesignTokens.Radius.row))
        .overlay {
            RoundedRectangle(cornerRadius: GitLabDesignTokens.Radius.row)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.45) : Color.clear)
        }
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: isHovering)
        .animation(reduceMotion ? nil : .smooth(duration: 0.16), value: isSelected)
    }

    @ViewBuilder
    private var rowContent: some View {
        if mode == .narrow {
            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.small) {
                identityAndTitle

                HStack(spacing: GitLabDesignTokens.Spacing.small) {
                    statusBadge
                    Spacer()
                    participantAndTime
                }
            }
        } else {
            HStack(alignment: .center, spacing: GitLabDesignTokens.Spacing.medium) {
                identityAndTitle
                statusBadge
                participantAndTime
            }
        }
    }

    private var identityAndTitle: some View {
        HStack(alignment: .top, spacing: GitLabDesignTokens.Spacing.medium) {
            Text(item.reference)
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)

            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xSmall) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(mode == .narrow ? 2 : 1)

                Text(item.project)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if item.labels.isEmpty == false {
                    GitLabWorkItemFlowLayout(spacing: 6) {
                        ForEach(item.labels, id: \.self) { label in
                            Text(label.name)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(labelTint(label).opacity(0.18), in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusBadge: some View {
        GitLabStatusBadge(
            title: item.status.title,
            systemImage: item.status.systemImage,
            severity: severity(item.status.semantic)
        )
    }

    private var participantAndTime: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            if item.participants.isEmpty == false {
                GitLabAvatarGroup(participants: item.participants)
            }

            Text(item.updatedTime)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(minWidth: 76, alignment: .trailing)
                .help(fullTimestamp)
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return GitLabDesignTokens.surfaceSelected
        }
        if isHovering {
            return GitLabDesignTokens.surfaceHover
        }
        return .clear
    }

    private var fullTimestamp: String {
        item.updatedAt?.formatted(date: .abbreviated, time: .standard) ?? item.updatedTime
    }

    private func selectAndOpen() {
        onSelect(item.id)
        if let webURL = item.webURL {
            openURL(webURL)
        }
    }

    private func severity(_ semantic: GitLabStatusSemantic) -> GitLabStatusSeverity {
        switch semantic {
        case .information:
            .information
        case .success:
            .success
        case .warning:
            .warning
        case .error:
            .error
        case .neutral:
            .neutral
        }
    }

    private func labelTint(_ label: GitLabLabel) -> Color {
        guard let value = label.color else { return .accentColor }
        let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let number = UInt64(hex, radix: 16) else { return .accentColor }
        return Color(
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255
        )
    }
}

private struct GitLabWorkItemFlowLayout: Layout {
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

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, points: [CGPoint]) {
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

#Preview("Work item row") {
    GitLabWorkItemRow(
        item: GitLabWorkItemPresentation(
            issue: GitLabIssue(
                id: 77,
                title: "A long issue title that verifies wrapping without hiding business labels",
                project: "ops/opshub",
                priority: .urgent,
                labels: ["Bug Production", "backend"],
                updatedTime: "2 hours ago",
                webURL: nil
            )
        ),
        mode: .narrow,
        isSelected: false,
        onSelect: { _ in },
        quickAction: { _ in }
    )
    .padding()
    .frame(width: 720)
}
