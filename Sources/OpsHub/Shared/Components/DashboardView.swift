import SwiftUI

struct DashboardView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                SummaryCard(title: "GitLab", value: "Ready", systemImage: "arrow.triangle.branch")
                SummaryCard(title: "Settings", value: "Runtime", systemImage: "gearshape")
            }

            EmptyStateView(
                systemImage: "rectangle.grid.2x2",
                title: "Dashboard",
                message: "Choose a module from the sidebar to manage your workspace."
            )
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, minHeight: 280)
            .opsHubTerminalSurface()

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpsHubTerminalTheme.surfaceSecondary)
        .navigationTitle("Dashboard")
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12, alignment: .top)
        ]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(">")
                    .foregroundStyle(OpsHubTerminalTheme.accent)
                Text("OPSHUB / DASHBOARD")
            }
            .font(.system(size: 26, weight: .bold, design: .monospaced))

            Text("runtime=ready · modules=available")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
