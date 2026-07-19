import Foundation

struct DevRoomVisibilitySettings: Equatable, Sendable {
    let selectedUserIDs: Set<Int>
}

protocol DevRoomVisibilitySettingsStoring {
    func load() -> DevRoomVisibilitySettings
    func save(_ settings: DevRoomVisibilitySettings)
}

final class DevRoomVisibilitySettingsStore: DevRoomVisibilitySettingsStoring {
    private let userDefaults: UserDefaults
    private let selectedUserIDsKey: String

    init(
        userDefaults: UserDefaults = .standard,
        selectedUserIDsKey: String = "devRoom.selectedUserIDs"
    ) {
        self.userDefaults = userDefaults
        self.selectedUserIDsKey = selectedUserIDsKey
    }

    func load() -> DevRoomVisibilitySettings {
        let ids = userDefaults.array(forKey: selectedUserIDsKey) as? [Int] ?? []
        return DevRoomVisibilitySettings(selectedUserIDs: Set(ids))
    }

    func save(_ settings: DevRoomVisibilitySettings) {
        userDefaults.set(settings.selectedUserIDs.sorted(), forKey: selectedUserIDsKey)
    }
}
