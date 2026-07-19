import XCTest
@testable import OpsHub

final class DevRoomVisibilitySettingsStoreTests: XCTestCase {
    func testNewStoreDefaultsToEmptyAllowlist() throws {
        let suite = "DevRoomVisibilitySettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DevRoomVisibilitySettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.load().selectedUserIDs, [])
    }

    func testSavePersistsSortedUniqueUserIDs() throws {
        let suite = "DevRoomVisibilitySettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DevRoomVisibilitySettingsStore(userDefaults: defaults)

        store.save(DevRoomVisibilitySettings(selectedUserIDs: [20, 10]))

        XCTAssertEqual(store.load().selectedUserIDs, [10, 20])
        XCTAssertEqual(defaults.array(forKey: "devRoom.selectedUserIDs") as? [Int], [10, 20])
    }
}
