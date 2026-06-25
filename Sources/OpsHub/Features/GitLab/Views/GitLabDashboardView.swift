import SwiftUI

struct GitLabDashboardView: View {
    private let statistics = [
        GitLabStatistic(icon: "arrow.triangle.merge", title: "Merge Requests", number: "12", subtitle: "4 waiting for review"),
        GitLabStatistic(icon: "exclamationmark.circle", title: "Issues", number: "28", subtitle: "9 assigned to you"),
        GitLabStatistic(icon: "play.circle", title: "Pipelines", number: "7", subtitle: "2 currently running"),
        GitLabStatistic(icon: "bell.badge", title: "Notifications", number: "16", subtitle: "5 unread mentions")
    ]

    private let columns = [
        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16, alignment: .top)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statisticGrid
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .navigationTitle("GitLab Dashboard")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("GitLab Dashboard")
                .font(.largeTitle.bold())
            Text("Overview of your GitLab work")
                .foregroundStyle(.secondary)
        }
    }

    private var statisticGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(statistics) { statistic in
                StatisticCard(
                    icon: statistic.icon,
                    title: statistic.title,
                    number: statistic.number,
                    subtitle: statistic.subtitle
                )
            }
        }
    }
}

private struct GitLabStatistic: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let number: String
    let subtitle: String
}

#Preview {
    NavigationStack {
        GitLabDashboardView()
    }
}
