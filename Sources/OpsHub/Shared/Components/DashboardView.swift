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
            .frame(maxWidth: .infinity, minHeight: 280)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Dashboard")
    }

    private var columns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 12, alignment: .top)
        ]
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dashboard")
                .font(.largeTitle.bold())
            Text("Runtime overview for OpsHub.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
}
