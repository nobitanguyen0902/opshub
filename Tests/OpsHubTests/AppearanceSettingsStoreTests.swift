import XCTest
@testable import OpsHub

@MainActor
final class AppearanceSettingsStoreTests: XCTestCase {
    func testNewStoreDefaultsToSystemTheme() throws {
        let suiteName = "AppearanceSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }

        let store = AppearanceSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.theme, .system)
        XCTAssertNil(store.theme.colorScheme)
    }

    func testStoreRestoresPersistedTheme() throws {
        let suiteName = "AppearanceSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set(AppTheme.dark.rawValue, forKey: AppearanceSettingsStore.themeKey)

        let store = AppearanceSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.theme, .dark)
        XCTAssertEqual(store.theme.colorScheme, .dark)
    }

    func testSetThemePersistsSelectionImmediately() throws {
        let suiteName = "AppearanceSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        let store = AppearanceSettingsStore(userDefaults: userDefaults)

        store.setTheme(.light)

        XCTAssertEqual(store.theme, .light)
        XCTAssertEqual(
            userDefaults.string(forKey: AppearanceSettingsStore.themeKey),
            AppTheme.light.rawValue
        )
    }

    func testUnknownPersistedValueFallsBackToSystemTheme() throws {
        let suiteName = "AppearanceSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { userDefaults.removePersistentDomain(forName: suiteName) }
        userDefaults.set("future-theme", forKey: AppearanceSettingsStore.themeKey)

        let store = AppearanceSettingsStore(userDefaults: userDefaults)

        XCTAssertEqual(store.theme, .system)
    }
}
