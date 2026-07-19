import SwiftUI

struct DevRoomHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let isStale: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dev Room")
                    .font(.largeTitle.bold())
                Text("\(GitLabWorkflowProject.path) • Open issues có assignee")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isStale {
                Label("Dữ liệu có thể đã cũ", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if let lastUpdated {
                Label(
                    lastUpdated.formatted(date: .omitted, time: .shortened),
                    systemImage: "clock"
                )
                .foregroundStyle(.secondary)
            }

            Button(action: onRefresh) {
                Label(
                    isRefreshing ? "Đang cập nhật" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .disabled(isRefreshing)
        }
    }
}
