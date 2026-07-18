import SwiftUI

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case devRoom
    case brew
    case gitLab
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard:
            return "Dashboard"
        case .devRoom:
            return "Dev Room"
        case .brew:
            return "Brew"
        case .gitLab:
            return "GitLab"
        case .settings:
            return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:
            return "rectangle.grid.2x2"
        case .devRoom:
            return "person.3.fill"
        case .brew:
            return "cup.and.saucer"
        case .gitLab:
            return "arrow.triangle.branch"
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
    @StateObject private var devRoomViewModel: DevRoomViewModel
    @StateObject private var gitLabViewModel: GitLabDashboardViewModel
    let settingsStore: any GitLabSettingsStoring

    init(
        navigationState: AppNavigationState,
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore()
    ) {
        self.navigationState = navigationState
        self.settingsStore = settingsStore
        let gitLabService = GitLabService(settingsStore: settingsStore)
        _devRoomViewModel = StateObject(
            wrappedValue: DevRoomViewModel(service: gitLabService)
        )
        _gitLabViewModel = StateObject(
            wrappedValue: GitLabDashboardViewModel(service: gitLabService)
        )
    }

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
            case .devRoom:
                DevRoomView(viewModel: devRoomViewModel)
            case .brew:
                BrewListView()
            case .gitLab:
                GitLabDashboardView(viewModel: gitLabViewModel)
            case .dashboard:
                DashboardView()
            case .settings:
                SettingsView(settingsStore: settingsStore)
            case nil:
                ContentUnavailableView("Select a page", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    ContentView(navigationState: AppNavigationState())
}
