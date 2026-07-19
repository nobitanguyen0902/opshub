import SwiftUI

enum DevRoomDetailDrawerLayout {
    static let preferredWidth: CGFloat = 360
    static let horizontalInset: CGFloat = 16

    struct Placement: Equatable {
        let width: CGFloat
        let trailingInset: CGFloat

        var leadingInset: CGFloat {
            max(0, availableWidth - width - trailingInset)
        }

        fileprivate let availableWidth: CGFloat
    }

    static func placement(for availableWidth: CGFloat) -> Placement {
        let boundedWidth = max(0, availableWidth)
        guard boundedWidth < preferredWidth + (horizontalInset * 2) else {
            return Placement(
                width: preferredWidth,
                trailingInset: 0,
                availableWidth: boundedWidth
            )
        }

        let inset = min(horizontalInset, boundedWidth / 2)
        return Placement(
            width: boundedWidth - (inset * 2),
            trailingInset: inset,
            availableWidth: boundedWidth
        )
    }
}

enum DevRoomDetailDrawerIssuePresentation {
    static func canOpen(_ issue: DevRoomIssue) -> Bool {
        issue.webURL != nil
    }

    static func accessibilityHint(for issue: DevRoomIssue) -> String {
        canOpen(issue) ? "Mở issue trên GitLab" : "Không có liên kết GitLab"
    }
}

struct DevRoomEmployeeDetailDrawer: View {
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var isHeadingFocused: Bool

    let summary: DevRoomEmployeeSummary
    let preferredStage: DevRoomWorkflowStage?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            stageCounts

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(stagesWithIssues) { stage in
                        issueGroup(for: stage)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { isHeadingFocused = true }
        .onExitCommand(perform: close)
    }

    var orderedStages: [DevRoomWorkflowStage] {
        guard let preferredStage else { return DevRoomWorkflowStage.allCases }
        return [preferredStage] + DevRoomWorkflowStage.allCases.filter { $0 != preferredStage }
    }

    var stagesWithIssues: [DevRoomWorkflowStage] {
        orderedStages.filter { summary.count(for: $0) > 0 }
    }

    func close() {
        onClose()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.employee.name)
                    .font(.title2.bold())
                    .accessibilityFocused($isHeadingFocused)
                if let username = summary.employee.username, username.isEmpty == false {
                    Text("@\(username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(summary.total) task")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Đóng chi tiết")
            .accessibilityHint("Nhấn Escape để đóng")
        }
    }

    private var stageCounts: some View {
        HStack(spacing: 6) {
            ForEach(DevRoomWorkflowStage.allCases) { stage in
                VStack(spacing: 3) {
                    Text("\(summary.count(for: stage))")
                        .font(.headline.monospacedDigit())
                    Text(stage.title)
                        .font(.caption2)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(DevRoomDesignTokens.color(for: stage))
                .background(
                    DevRoomDesignTokens.color(for: stage).opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .accessibilityLabel("\(stage.title), \(summary.count(for: stage)) task")
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = summary.employee.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                fallbackAvatar
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            fallbackAvatar
                .frame(width: 44, height: 44)
        }
    }

    private var fallbackAvatar: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }

    private func issueGroup(for stage: DevRoomWorkflowStage) -> some View {
        let issues = summary.issues.filter { $0.stage == stage }
        return VStack(alignment: .leading, spacing: 8) {
            Label(stage.title, systemImage: "circle.fill")
                .font(.headline)
                .foregroundStyle(DevRoomDesignTokens.color(for: stage))

            ForEach(issues) { issue in
                issueButton(issue)
            }
        }
    }

    private func issueButton(_ issue: DevRoomIssue) -> some View {
        Button {
            if let webURL = issue.webURL {
                openURL(webURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("#\(issue.iid)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(issue.title)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
                HStack {
                    if let updatedAt = issue.updatedAt {
                        Text(updatedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(issue.stage.title)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            DevRoomDesignTokens.color(for: issue.stage).opacity(0.14),
                            in: Capsule()
                        )
                        .foregroundStyle(DevRoomDesignTokens.color(for: issue.stage))
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .disabled(DevRoomDetailDrawerIssuePresentation.canOpen(issue) == false)
        .accessibilityHint(DevRoomDetailDrawerIssuePresentation.accessibilityHint(for: issue))
    }
}
