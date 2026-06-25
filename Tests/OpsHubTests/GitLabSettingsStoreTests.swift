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

    func testSaveStoresLastConnectionTestResultInUserDefaults() throws {
        let suiteName = "GitLabSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let keychainTokenStore = InMemoryKeychainTokenStore()
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            keychainTokenStore: keychainTokenStore
        )
        let testedAt = Date(timeIntervalSince1970: 1_780_000_000)

        try store.save(
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret",
                lastConnectionTestResult: .connected,
                lastConnectionTestedAt: testedAt
            )
        )

        XCTAssertEqual(userDefaults.string(forKey: "gitlab.connectionTestResult"), "connected")
        XCTAssertEqual(userDefaults.object(forKey: "gitlab.connectionTestedAt") as? Date, testedAt)
        XCTAssertEqual(
            store.load(),
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret",
                lastConnectionTestResult: .connected,
                lastConnectionTestedAt: testedAt
            )
        )

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testSaveClearsLastConnectionTestResultWhenSettingsAreSavedWithoutResult() throws {
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
                personalAccessToken: "glpat-secret",
                lastConnectionTestResult: .connected,
                lastConnectionTestedAt: Date(timeIntervalSince1970: 1_780_000_000)
            )
        )
        try store.save(
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret"
            )
        )

        XCTAssertNil(userDefaults.string(forKey: "gitlab.connectionTestResult"))
        XCTAssertNil(userDefaults.object(forKey: "gitlab.connectionTestedAt"))
        XCTAssertNil(store.load().lastConnectionTestResult)
        XCTAssertNil(store.load().lastConnectionTestedAt)

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
