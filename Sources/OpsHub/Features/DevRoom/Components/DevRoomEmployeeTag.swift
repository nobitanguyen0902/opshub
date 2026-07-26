import SwiftUI

struct DevRoomEmployeeTag: View {
    let summary: DevRoomEmployeeSummary

    var body: some View {
        HStack(spacing: 8) {
            avatar

            VStack(alignment: .leading, spacing: 2) {
                Text(summary.employee.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Text("\(summary.total) task")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let stage = summary.representativeStage {
                Circle()
                    .fill(DevRoomDesignTokens.color(for: stage))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            DevRoomDesignTokens.surfacePrimary.opacity(0.96),
            in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                .stroke(DevRoomDesignTokens.borderStrong)
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
            .frame(width: 28, height: 28)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
        }
    }
}
