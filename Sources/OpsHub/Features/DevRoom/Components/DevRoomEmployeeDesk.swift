import SwiftUI

struct DevRoomEmployeeDesk: View {
    let summary: DevRoomEmployeeSummary
    let selectedStage: DevRoomWorkflowStage?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                employeeCard
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.10))
                    .frame(height: 100)
                    .overlay {
                        Image(systemName: "laptopcomputer")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(summary.employee.name), \(summary.total) task")
    }

    private var employeeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.employee.name)
                        .font(.headline)
                    Text("\(summary.total) task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(summary.previewIssues(for: selectedStage)) { issue in
                Text("• #\(issue.iid) \(issue.title)")
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                ForEach(DevRoomWorkflowStage.allCases) { stage in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DevRoomDesignTokens.color(for: stage))
                            .frame(width: 7, height: 7)
                        Text("\(summary.count(for: stage))")
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                .stroke(Color(nsColor: .separatorColor))
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
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
        }
    }
}
