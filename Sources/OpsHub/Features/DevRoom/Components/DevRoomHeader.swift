import SwiftUI

struct DevRoomHeader: View {
    let lastUpdated: Date?
    let isRefreshing: Bool
    let isStale: Bool
    let onRefresh: () -> Void

    var body: some View {
        OpsHubFeatureHeader(
            eyebrow: "OPSHUB / DEV ROOM",
            title: "Team workspace",
            metadata: metadata
        ) {
            Button(action: onRefresh) {
                Label(
                    isRefreshing ? "Đang cập nhật" : "Refresh",
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.plain)
            .opsHubTerminalControl()
            .disabled(isRefreshing)
            .accessibilityLabel(isRefreshing ? "Đang cập nhật Dev Room" : "Refresh Dev Room")
        } status: {
            if isStale {
                Label("Dữ liệu có thể đã cũ", systemImage: "exclamationmark.triangle")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.orange)
            }
        }
    }

    private var metadata: String {
        let source = "project=\(GitLabWorkflowProject.path) · source=assigned-open-issues"
        guard let lastUpdated else {
            return "\(source) · updated=never"
        }
        return "\(source) · updated=\(lastUpdated.formatted(date: .omitted, time: .shortened))"
    }
}
