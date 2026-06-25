import SwiftUI

enum AppSection: Hashable {
    case brew
    case gitLab
    case settings
}

struct ContentView: View {
    @State private var selection: AppSection? = .brew

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                NavigationLink(value: AppSection.brew) {
                    Label("Brew", systemImage: "cup.and.saucer")
                }

                NavigationLink(value: AppSection.gitLab) {
                    Label("GitLab", systemImage: "arrow.triangle.branch")
                }

                NavigationLink(value: AppSection.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            .navigationTitle("OpsHub")
            .listStyle(.sidebar)
        } detail: {
            switch selection {
            case .brew:
                BrewListView()
            case .gitLab:
                GitLabDashboardView()
            case .settings:
                SettingsView()
            case nil:
                ContentUnavailableView("Select a module", systemImage: "sidebar.left")
            }
        }
    }
}
