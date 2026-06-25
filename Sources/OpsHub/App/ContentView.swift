import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case gitLab
    case dashboard
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .gitLab:
            return "GitLab"
        case .dashboard:
            return "Dashboard"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .gitLab:
            return "arrow.triangle.branch"
        case .dashboard:
            return "rectangle.grid.2x2"
        case .settings:
            return "gearshape"
        }
    }
}

final class AppNavigationState: ObservableObject {
    @Published var selection: AppSection? = .gitLab
}

struct ContentView: View {
    @ObservedObject var navigationState: AppNavigationState

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationState.selection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .navigationTitle("OpsHub")
            .listStyle(.sidebar)
        } detail: {
            switch navigationState.selection {
            case .gitLab:
                GitLabDashboardView()
            case .dashboard:
                DashboardView()
            case .settings:
                SettingsView()
            case nil:
                ContentUnavailableView("Select a page", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    ContentView(navigationState: AppNavigationState())
}
