import SwiftUI

@main
struct OpsHubApp: App {
    @StateObject private var navigationState = AppNavigationState()

    private let updateManager: UpdateManager

    init() {
        updateManager = UpdateManager()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(navigationState: navigationState)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(after: .appSettings) {
                CheckForUpdatesCommand(updateManager: updateManager)
            }
        }

        Settings {
            SettingsView()
                .frame(width: 520, height: 420)
        }
    }
}

private struct CheckForUpdatesCommand: View {
    @ObservedObject var updateManager: UpdateManager

    var body: some View {
        Button("Check for Updates...") {
            updateManager.checkForUpdates()
        }
        .disabled(!updateManager.canCheckForUpdates)
    }
}
