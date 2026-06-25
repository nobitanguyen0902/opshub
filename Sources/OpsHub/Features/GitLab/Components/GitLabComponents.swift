import SwiftUI

struct StatisticCard: View {
    let icon: String
    let title: String
    let number: String
    let subtitle: String

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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct MergeRequestsCard: View {
    let mergeRequests: [GitLabMergeRequest]
    @Binding var selectedMergeRequestID: GitLabMergeRequest.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Merge Requests")
                    .font(.headline)

                Text("\(mergeRequests.count)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.tertiary, in: Capsule())

                Spacer()

                Button("View All") {}
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)

            VStack(spacing: 0) {
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
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
            .background(selectionBackground)
        }
        .buttonStyle(.plain)
    }

    private var selectionBackground: some ShapeStyle {
        isSelected ? Color.accentColor.opacity(0.14) : Color.clear
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
            selectedMergeRequestID: .constant(1842)
        )
    }
    .padding()
}
