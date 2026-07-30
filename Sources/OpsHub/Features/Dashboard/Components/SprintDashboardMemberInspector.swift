import SwiftUI

enum SprintDashboardInspectorLayout {
    static let preferredWidth: CGFloat = 460
    static let horizontalInset: CGFloat = 16

    struct Placement: Equatable {
        let width: CGFloat
        let trailingInset: CGFloat
    }

    static func placement(for availableWidth: CGFloat) -> Placement {
        let boundedWidth = max(0, availableWidth)
        guard boundedWidth < preferredWidth + (horizontalInset * 2) else {
            return Placement(width: preferredWidth, trailingInset: 0)
        }

        let inset = min(horizontalInset, boundedWidth / 2)
        return Placement(
            width: boundedWidth - (inset * 2),
            trailingInset: inset
        )
    }
}

enum SprintDashboardIssuePresentation {
    private static let workflowLabels = [
        "Merged",
        "ToProduction",
        "Passed",
        "Testing",
        "ToTest",
        "Doing",
        "Todo"
    ]

    static func workflowLabel(for issue: SprintDashboardIssue) -> String? {
        workflowLabels.first { expected in
            issue.labels.contains { label in
                label
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .caseInsensitiveCompare(expected) == .orderedSame
            }
        }
    }

    static func canOpen(_ issue: SprintDashboardIssue) -> Bool {
        issue.webURL != nil
    }
}

struct SprintMemberAvatar: View {
    let member: SprintDashboardMember?
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let avatarURL = member?.avatarURL {
                AsyncImage(url: avatarURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(OpsHubTerminalTheme.borderStrong)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var fallback: some View {
        if member == nil {
            ZStack {
                OpsHubTerminalTheme.selected
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.16)
                    .foregroundStyle(OpsHubTerminalTheme.accent)
            }
        } else {
            ZStack {
                OpsHubTerminalTheme.selected
                Text(initials)
                    .font(
                        .system(
                            size: max(9, size * 0.34),
                            weight: .bold,
                            design: .monospaced
                        )
                    )
                    .foregroundStyle(OpsHubTerminalTheme.accent)
            }
        }
    }

    private var initials: String {
        guard let name = member?.name else { return "—" }
        return name
            .split(separator: " ")
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
    }
}

struct SprintDashboardMemberInspector: View {
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var isHeadingFocused: Bool

    let summary: SprintDashboardMemberSummary
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            progressSummary
            Divider()

            if summary.issues.isEmpty {
                emptyState
            } else {
                taskList
            }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .onAppear { isHeadingFocused = true }
        .onExitCommand(perform: close)
    }

    func close() {
        onClose()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            SprintMemberAvatar(member: summary.member, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(summary.member?.name ?? "Unassigned")
                    .font(.system(.title2, design: .monospaced).bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isHeadingFocused)

                Text(identityMetadata)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)

                Text("\(summary.ticketCount) sprint tasks")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close member tasks")
            .accessibilityHint("Press Escape to close")
        }
    }

    private var progressSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(
                    "\(summary.releasedCount) released",
                    systemImage: "checkmark.circle"
                )
                .foregroundStyle(.green)

                Spacer()

                Text(
                    summary.progress.formatted(
                        .percent.precision(.fractionLength(0))
                    )
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))

            ProgressView(value: summary.progress)
                .progressViewStyle(.linear)
                .tint(OpsHubTerminalTheme.accent)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Release progress")
        .accessibilityValue(
            "\(summary.releasedCount) of \(summary.ticketCount) released"
        )
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(summary.issues) { issue in
                    taskButton(issue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No sprint tasks",
            systemImage: "tray",
            description: Text(
                "This member no longer has tasks in the selected milestone."
            )
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func taskButton(_ issue: SprintDashboardIssue) -> some View {
        Button {
            if let webURL = issue.webURL {
                openURL(webURL)
            }
        } label: {
            SprintDashboardInspectorTaskRow(issue: issue)
        }
        .buttonStyle(.plain)
        .disabled(
            SprintDashboardIssuePresentation.canOpen(issue) == false
        )
        .accessibilityHint(
            issue.webURL == nil
                ? "GitLab link is unavailable"
                : "Opens this issue in GitLab"
        )
    }

    private var identityMetadata: String {
        summary.member?.username.map { "@\($0)" } ?? "Needs an owner"
    }
}

private struct SprintDashboardInspectorTaskRow: View {
    let issue: SprintDashboardIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            titleRow

            Text("\(issue.project) #\(issue.iid)")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)

            metadataRow
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .background(
            OpsHubTerminalTheme.surfacePrimary,
            in: RoundedRectangle(
                cornerRadius: OpsHubTerminalTheme.containerRadius
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: OpsHubTerminalTheme.containerRadius
            )
            .strokeBorder(OpsHubTerminalTheme.borderSubtle)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(issue.title)
                .font(.system(.callout, design: .monospaced).weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if issue.webURL != nil {
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(OpsHubTerminalTheme.accent)
                    .accessibilityHidden(true)
            }
        }
    }

    private var metadataRow: some View {
        HStack(spacing: 8) {
            if let workflowLabel = SprintDashboardIssuePresentation
                .workflowLabel(for: issue) {
                Text(workflowLabel.uppercased())
                    .font(
                        .system(
                            .caption2,
                            design: .monospaced
                        ).weight(.semibold)
                    )
                    .foregroundStyle(OpsHubTerminalTheme.accent)
            }

            releaseState

            Spacer(minLength: 4)

            if let updatedAt = issue.updatedAt {
                Text(updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var releaseState: some View {
        if SprintDashboardAggregator.isReleased(issue) {
            Label("Released", systemImage: "checkmark.circle.fill")
                .font(
                    .system(
                        .caption2,
                        design: .monospaced
                    ).weight(.semibold)
                )
                .foregroundStyle(.green)
        } else {
            Label("In progress", systemImage: "circle.dotted")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityLabel: String {
        let releaseState = SprintDashboardAggregator.isReleased(issue)
            ? "released"
            : "in progress"
        return "\(issue.title), \(issue.project) issue \(issue.iid), \(releaseState)"
    }
}
