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

    func testKeychainTokenStoreDoesNotUseDataProtectionKeychainByDefault() {
        let tokenStore = KeychainTokenStore(
            service: "OpsHub.GitLabTests",
            account: "PersonalAccessToken"
        )

        XCTAssertNil(tokenStore.baseQuery[kSecUseDataProtectionKeychain as String])
    }

    func testKeychainTokenStoreCanOptIntoDataProtectionKeychain() {
        let tokenStore = KeychainTokenStore(
            service: "OpsHub.GitLabTests",
            account: "PersonalAccessToken",
            usesDataProtectionKeychain: true
        )

        XCTAssertEqual(tokenStore.baseQuery[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }

    @MainActor
    func testFailedGitLabSaveDoesNotPersistOrApplyDevRoomDraft() async {
        let memberSelectionViewModel = DevRoomMemberSelectionViewModel(
            service: SettingsMemberService(members: [settingsMember(id: 20)]),
            initialSelectedUserIDs: [20]
        )
        await memberSelectionViewModel.loadMembers()
        let visibilityStore = RecordingDevRoomVisibilityStore()
        var appliedIDs: Set<Int>?

        XCTAssertThrowsError(
            try SettingsSaveIntegration.save(
                gitLabSettings: GitLabSettings(gitLabURL: "https://gitlab.example.com", personalAccessToken: "token"),
                settingsStore: ThrowingGitLabSettingsStore(),
                visibilityStore: visibilityStore,
                memberSelectionViewModel: memberSelectionViewModel,
                onDevRoomVisibilitySaved: { appliedIDs = $0 }
            )
        )

        XCTAssertTrue(visibilityStore.savedSettings.isEmpty)
        XCTAssertNil(appliedIDs)
        XCTAssertEqual(memberSelectionViewModel.draftSelectedUserIDs, [20])
    }

    @MainActor
    func testSuccessfulSavePersistsAndAppliesLoadedDevRoomDraftAfterGitLabSettings() async throws {
        let memberSelectionViewModel = DevRoomMemberSelectionViewModel(
            service: SettingsMemberService(members: [settingsMember(id: 10), settingsMember(id: 20)]),
            initialSelectedUserIDs: [20]
        )
        await memberSelectionViewModel.loadMembers()
        memberSelectionViewModel.toggle(10)

        let visibilityStore = RecordingDevRoomVisibilityStore()
        let settingsStore = RecordingGitLabSettingsStore()
        var callbackWasCalledAfterGitLabSave = false
        var appliedIDs: Set<Int>?

        try SettingsSaveIntegration.save(
            gitLabSettings: GitLabSettings(gitLabURL: "https://gitlab.example.com", personalAccessToken: "token"),
            settingsStore: settingsStore,
            visibilityStore: visibilityStore,
            memberSelectionViewModel: memberSelectionViewModel,
            onDevRoomVisibilitySaved: { ids in
                callbackWasCalledAfterGitLabSave = settingsStore.savedSettings.count == 1
                appliedIDs = ids
            }
        )

        XCTAssertEqual(visibilityStore.savedSettings.map(\.selectedUserIDs), [[10, 20]])
        XCTAssertEqual(appliedIDs, [10, 20])
        XCTAssertTrue(callbackWasCalledAfterGitLabSave)
    }

    @MainActor
    func testFailedMemberLoadDoesNotOverwriteSavedDevRoomAllowlist() async throws {
        let memberSelectionViewModel = DevRoomMemberSelectionViewModel(
            service: FailingSettingsMemberService(),
            initialSelectedUserIDs: [20]
        )
        await memberSelectionViewModel.loadMembers()
        let visibilityStore = RecordingDevRoomVisibilityStore()
        let settingsStore = RecordingGitLabSettingsStore()
        var appliedIDs: Set<Int>?

        try SettingsSaveIntegration.save(
            gitLabSettings: GitLabSettings(gitLabURL: "https://gitlab.example.com", personalAccessToken: "token"),
            settingsStore: settingsStore,
            visibilityStore: visibilityStore,
            memberSelectionViewModel: memberSelectionViewModel,
            onDevRoomVisibilitySaved: { appliedIDs = $0 }
        )

        XCTAssertEqual(settingsStore.savedSettings.count, 1)
        XCTAssertTrue(visibilityStore.savedSettings.isEmpty)
        XCTAssertNil(appliedIDs)
        XCTAssertEqual(memberSelectionViewModel.draftSelectedUserIDs, [20])
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

private final class RecordingDevRoomVisibilityStore: DevRoomVisibilitySettingsStoring {
    private(set) var savedSettings: [DevRoomVisibilitySettings] = []

    func load() -> DevRoomVisibilitySettings {
        DevRoomVisibilitySettings(selectedUserIDs: [])
    }

    func save(_ settings: DevRoomVisibilitySettings) {
        savedSettings.append(settings)
    }
}

private final class RecordingGitLabSettingsStore: GitLabSettingsStoring {
    private(set) var savedSettings: [GitLabSettings] = []

    func load() -> GitLabSettings {
        GitLabSettings(gitLabURL: "", personalAccessToken: "")
    }

    func save(_ settings: GitLabSettings) throws {
        savedSettings.append(settings)
    }
}

private struct ThrowingGitLabSettingsStore: GitLabSettingsStoring {
    func load() -> GitLabSettings {
        GitLabSettings(gitLabURL: "", personalAccessToken: "")
    }

    func save(_ settings: GitLabSettings) throws {
        throw GitLabSettingsStoreError.invalidTokenData
    }
}

private actor SettingsMemberService: DevRoomMemberServicing {
    let members: [DevRoomProjectMember]

    init(members: [DevRoomProjectMember]) {
        self.members = members
    }

    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        members
    }
}

private actor FailingSettingsMemberService: DevRoomMemberServicing {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        throw SettingsMemberServiceError.unavailable
    }
}

private enum SettingsMemberServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "GitLab members are unavailable."
    }
}

private func settingsMember(id: Int) -> DevRoomProjectMember {
    DevRoomProjectMember(
        id: id,
        username: "member\(id)",
        name: "Member \(id)",
        avatarURL: nil,
        accessLevel: 30
    )
}
