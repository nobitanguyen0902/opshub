import AppKit
import SwiftUI

@main
struct OpsHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var navigationState = AppNavigationState()

    private let updateManager: UpdateManager
    private let gitLabSettingsStore: GitLabSettingsStore

    init() {
        updateManager = UpdateManager()
        gitLabSettingsStore = GitLabSettingsStore()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                navigationState: navigationState,
                settingsStore: gitLabSettingsStore
            )
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(after: .appSettings) {
                CheckForUpdatesCommand(updateManager: updateManager)
            }
        }

        Settings {
            SettingsView(settingsStore: gitLabSettingsStore)
                .frame(width: 520, height: 420)
        }
    }
}

private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        setApplicationIcon()
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @MainActor
    private func setApplicationIcon() {
        guard let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
              let icon = NSImage(contentsOf: iconURL) else {
            return
        }

        NSApplication.shared.applicationIconImage = icon
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
