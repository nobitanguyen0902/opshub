import Combine
import Sparkle

@MainActor
final class UpdateManager: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController
    private let checksForUpdatesOnLaunch: Bool
    private var canCheckForUpdatesCancellable: AnyCancellable?

    init(
        startingUpdater: Bool = true,
        checksForUpdatesOnLaunch: Bool = UpdateManager.defaultChecksForUpdatesOnLaunch
    ) {
        // Sparkle reads SUFeedURL, SUPublicEDKey, and automatic update defaults
        // from the app bundle's Info.plist when the updater starts.
        self.checksForUpdatesOnLaunch = checksForUpdatesOnLaunch
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        canCheckForUpdates = updaterController.updater.canCheckForUpdates
        canCheckForUpdatesCancellable = updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .sink { [weak self] canCheckForUpdates in
                self?.canCheckForUpdates = canCheckForUpdates
            }

        if startingUpdater {
            checkForUpdatesInBackgroundOnLaunchIfAllowed()
        }
    }

    func startUpdater() {
        updaterController.startUpdater()
        checkForUpdatesInBackgroundOnLaunchIfAllowed()
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    private func checkForUpdatesInBackgroundOnLaunchIfAllowed() {
        guard checksForUpdatesOnLaunch,
              updaterController.updater.automaticallyChecksForUpdates else {
            return
        }

        updaterController.updater.checkForUpdatesInBackground()
    }

    private static var defaultChecksForUpdatesOnLaunch: Bool {
        Bundle.main.object(forInfoDictionaryKey: "OpsHubCheckForUpdatesOnLaunch") as? Bool ?? true
    }
}
