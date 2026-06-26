import Foundation
import XCTest
@testable import OpsHub

final class GitLabSettingsStoreTests: XCTestCase {
    func testInitLoadsExistingGitLabSettings() throws {
        let suiteName = "GitLabSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.set("https://gitlab.local", forKey: "gitlab.url")

        let tokenStore = InMemoryGitLabTokenStore(token: "existing-token")
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            tokenStore: tokenStore
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
        let tokenStore = InMemoryGitLabTokenStore()
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            tokenStore: tokenStore
        )

        try store.save(
            GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "glpat-secret"
            )
        )

        XCTAssertEqual(userDefaults.string(forKey: "gitlab.url"), "https://gitlab.example.com")
        XCTAssertEqual(try tokenStore.readToken(), "glpat-secret")
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
        let tokenStore = InMemoryGitLabTokenStore()
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            tokenStore: tokenStore
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
        let tokenStore = InMemoryGitLabTokenStore()
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            tokenStore: tokenStore
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

    func testSaveDoesNotPersistSettingsWhenTokenStoreFails() throws {
        let suiteName = "GitLabSettingsStoreTests.\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let store = GitLabSettingsStore(
            userDefaults: userDefaults,
            tokenStore: FailingGitLabTokenStore()
        )

        XCTAssertThrowsError(
            try store.save(
                GitLabSettings(
                    gitLabURL: "https://gitlab.example.com",
                    personalAccessToken: "glpat-secret",
                    lastConnectionTestResult: .connected,
                    lastConnectionTestedAt: Date(timeIntervalSince1970: 1_780_000_000)
                )
            )
        )
        XCTAssertNil(userDefaults.string(forKey: "gitlab.url"))
        XCTAssertNil(userDefaults.string(forKey: "gitlab.connectionTestResult"))
        XCTAssertNil(userDefaults.object(forKey: "gitlab.connectionTestedAt"))
        XCTAssertEqual(store.load(), GitLabSettings(gitLabURL: "", personalAccessToken: ""))

        userDefaults.removePersistentDomain(forName: suiteName)
    }

    func testLocalGitLabTokenStoreSavesReadsAndClearsToken() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("GitLabSettingsStoreTests.\(UUID().uuidString)", isDirectory: true)
        let tokenFileURL = directoryURL.appendingPathComponent("token")
        let tokenStore = LocalGitLabTokenStore(tokenFileURL: tokenFileURL)

        try tokenStore.saveToken("glpat-local")

        XCTAssertEqual(try tokenStore.readToken(), "glpat-local")

        try tokenStore.saveToken("")

        XCTAssertEqual(try tokenStore.readToken(), "")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tokenFileURL.path))

        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class InMemoryGitLabTokenStore: GitLabTokenStoring {
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

private struct FailingGitLabTokenStore: GitLabTokenStoring {
    func readToken() throws -> String {
        ""
    }

    func saveToken(_ token: String) throws {
        throw GitLabSettingsStoreError.invalidTokenData
    }
}
