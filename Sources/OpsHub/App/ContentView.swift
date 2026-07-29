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
    private let devRoomViewModel: DevRoomViewModel
    @StateObject private var gitLabViewModel: GitLabDashboardViewModel
    let settingsStore: any GitLabSettingsStoring
    private let visibilityStore: any DevRoomVisibilitySettingsStoring
    private let memberService: any DevRoomMemberServicing
    @ObservedObject private var appearanceStore: AppearanceSettingsStore

    init(
        navigationState: AppNavigationState,
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore(),
        visibilityStore: any DevRoomVisibilitySettingsStoring = DevRoomVisibilitySettingsStore(),
        gitLabService: GitLabService? = nil,
        devRoomViewModel: DevRoomViewModel? = nil,
        memberService: (any DevRoomMemberServicing)? = nil,
        appearanceStore: AppearanceSettingsStore = AppearanceSettingsStore()
    ) {
        self.navigationState = navigationState
        self.settingsStore = settingsStore
        self.visibilityStore = visibilityStore
        let resolvedGitLabService = gitLabService ?? GitLabService(settingsStore: settingsStore)
        self.memberService = memberService ?? resolvedGitLabService
        self.appearanceStore = appearanceStore
        self.devRoomViewModel = devRoomViewModel ?? DevRoomViewModel(
            service: resolvedGitLabService,
            selectedUserIDs: visibilityStore.load().selectedUserIDs
        )
        _gitLabViewModel = StateObject(
            wrappedValue: GitLabDashboardViewModel(service: resolvedGitLabService)
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $navigationState.selection) {
                ForEach(AppSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
            }
            .navigationTitle("OpsHub")
            .listStyle(.sidebar)
            .tint(OpsHubTerminalTheme.accent)
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
                SettingsView(
                    settingsStore: settingsStore,
                    visibilityStore: visibilityStore,
                    memberService: memberService,
                    appearanceStore: appearanceStore,
                    onDevRoomVisibilitySaved: { ids in
                        devRoomViewModel.applySelectedUserIDs(ids)
                    }
                )
            case nil:
                ContentUnavailableView("Select a page", systemImage: "sidebar.left")
            }
        }
    }
}

#Preview {
    ContentView(navigationState: AppNavigationState())
}
