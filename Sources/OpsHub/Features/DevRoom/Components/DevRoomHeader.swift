import SwiftUI

struct DevRoomHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let isStale: Bool
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(">")
                        .foregroundStyle(DevRoomDesignTokens.terminalAccent)
                    Text("OPSHUB / DEV ROOM")
                }
                .font(.system(size: 26, weight: .bold, design: .monospaced))

                Text("project=\(GitLabWorkflowProject.path) · source=assigned-open-issues")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isStale {
                Label("Dữ liệu có thể đã cũ", systemImage: "exclamationmark.triangle")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            }

            if let lastUpdated {
                Label(
                    lastUpdated.formatted(date: .omitted, time: .shortened),
                    systemImage: "clock"
                )
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            Button(action: onRefresh) {
                Label(
                    isRefreshing ? "Đang cập nhật" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .opsHubTerminalControl()
            .disabled(isRefreshing)
        }
    }
}
