import AppKit
import SwiftUI

@main
struct OpsHubApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var navigationState = AppNavigationState()
    @StateObject private var devRoomViewModel: DevRoomViewModel
    @StateObject private var appearanceStore: AppearanceSettingsStore

    private let updateManager: UpdateManager
    private let gitLabSettingsStore: GitLabSettingsStore
    private let devRoomVisibilityStore: DevRoomVisibilitySettingsStore
    private let gitLabService: GitLabService

    init() {
        let settingsStore = GitLabSettingsStore()
        let visibilityStore = DevRoomVisibilitySettingsStore()
        let service = GitLabService(settingsStore: settingsStore)
        let appearanceStore = AppearanceSettingsStore()

        updateManager = UpdateManager()
        gitLabSettingsStore = settingsStore
        devRoomVisibilityStore = visibilityStore
        gitLabService = service
        _appearanceStore = StateObject(wrappedValue: appearanceStore)
        _devRoomViewModel = StateObject(
            wrappedValue: DevRoomViewModel(
                service: service,
                selectedUserIDs: visibilityStore.load().selectedUserIDs
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                navigationState: navigationState,
                settingsStore: gitLabSettingsStore,
                visibilityStore: devRoomVisibilityStore,
                gitLabService: gitLabService,
                devRoomViewModel: devRoomViewModel,
                appearanceStore: appearanceStore
            )
            .preferredColorScheme(appearanceStore.theme.colorScheme)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(after: .appSettings) {
                CheckForUpdatesCommand(updateManager: updateManager)
            }
        }

        Settings {
            SettingsView(
                settingsStore: gitLabSettingsStore,
                gitLabService: gitLabService,
                visibilityStore: devRoomVisibilityStore,
                memberService: gitLabService,
                appearanceStore: appearanceStore,
                onDevRoomVisibilitySaved: { ids in
                    devRoomViewModel.applySelectedUserIDs(ids)
                }
            )
                .frame(width: 560, height: 520)
                .preferredColorScheme(appearanceStore.theme.colorScheme)
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
        guard let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
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
