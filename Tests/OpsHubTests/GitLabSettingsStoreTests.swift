import Foundation
import XCTest
@testable import OpsHub

final class GitLabSettingsStoreTests: XCTestCase {
    func testInitLoadsExistingGitLabSettings() throws {
        let suiteName = "GitLabSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.set("https://gitlab.local", forKey: "gitlab.url")

        let keychainTokenStore = InMemoryKeychainTokenStore(token: "existing-token")
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            keychainTokenStore: keychainTokenStore
        )

        XCTAssertEqual(
            store.load(),
            GitLabSettings(
                gitLabURL: "https://gitlab.local",
                personalAccessToken: "existing-token"
            )
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSaveStoresGitLabURLInUserDefaultsAndTokenInKeychainStore() throws {
        let suiteName = "GitLabSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychainTokenStore = InMemoryKeychainTokenStore()
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            keychainTokenStore: keychainTokenStore
        )

        try store.save(
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret"
            )
        )

        XCTAssertEqual(userDefaults.string(forKey: "gitlab.url"), "https://gitlab.example.com")
        XCTAssertEqual(try keychainTokenStore.readToken(), "glpat-secret")
        XCTAssertEqual(
            store.load(),
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret"
            )
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }
}

private final class InMemoryKeychainTokenStore: KeychainTokenStoring {
    private var token: String

    init(token: String = "") {
        self.token = token
    }

    func readToken() throws -> String {
        token
    }

    func saveToken(_ token: String) throws {
        self.token = token
    }
}
