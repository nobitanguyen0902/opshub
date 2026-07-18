import SwiftUI

struct DevRoomEmployeeDetailPanel: View {
    @Environment(\.openURL) private var openURL

    let summary: DevRoomEmployeeSummary
    let preferredStage: DevRoomWorkflowStage?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.employee.name)
                        .font(.title2.bold())
                    Text("\(summary.total) task")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Đóng chi tiết")
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(orderedStages) { stage in
                        let issues = summary.issues.filter { $0.stage == stage }
                        if issues.isEmpty == false {
                            VStack(alignment: .leading, spacing: 8) {
                                Label(stage.title, systemImage: "circle.fill")
                                    .font(.headline)
                                    .foregroundStyle(DevRoomDesignTokens.color(for: stage))

                                ForEach(issues) { issue in
                                    issueButton(issue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = summary.employee.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
        }
    }

    private var orderedStages: [DevRoomWorkflowStage] {
        guard let preferredStage else { return DevRoomWorkflowStage.allCases }
        return [preferredStage] + DevRoomWorkflowStage.allCases.filter { $0 != preferredStage }
    }

    private func issueButton(_ issue: DevRoomIssue) -> some View {
        Button {
            if let webURL = issue.webURL {
                openURL(webURL)
            }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("#\(issue.iid) \(issue.title)")
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let updatedAt = issue.updatedAt {
                    Text(updatedAt.formatted())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(
                Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .buttonStyle(.plain)
        .disabled(issue.webURL == nil)
    }
}
