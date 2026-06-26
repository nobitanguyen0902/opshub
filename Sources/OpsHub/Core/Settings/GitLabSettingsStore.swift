import Foundation
import Security

/// Stores non-secret GitLab settings in UserDefaults and the token in the active token store.
final class GitLabSettingsStore: GitLabSettingsStoring {
    private let userDefaults: UserDefaults
    private let tokenStore: any GitLabTokenStoring
    private let gitLabURLKey: String
    private let connectionTestResultKey: String
    private let connectionTestedAtKey: String
    private var currentSettings: GitLabSettings

    init(
        userDefaults: UserDefaults = .standard,
        tokenStore: any GitLabTokenStoring = GitLabSettingsStore.defaultTokenStore(),
        gitLabURLKey: String = "gitlab.url",
        connectionTestResultKey: String = "gitlab.connectionTestResult",
        connectionTestedAtKey: String = "gitlab.connectionTestedAt"
    ) {
        self.userDefaults = userDefaults
        self.tokenStore = tokenStore
        self.gitLabURLKey = gitLabURLKey
        self.connectionTestResultKey = connectionTestResultKey
        self.connectionTestedAtKey = connectionTestedAtKey
        currentSettings = GitLabSettings(
            gitLabURL: "",
            personalAccessToken: "",
            lastConnectionTestResult: nil,
            lastConnectionTestedAt: nil
        )
        currentSettings = readSettings()
    }

    func load() -> GitLabSettings {
        currentSettings
    }

    func save(_ settings: GitLabSettings) throws {
        try tokenStore.saveToken(settings.personalAccessToken)

        userDefaults.set(settings.gitLabURL, forKey: gitLabURLKey)
        if let lastConnectionTestResult = settings.lastConnectionTestResult {
            userDefaults.set(lastConnectionTestResult.rawValue, forKey: connectionTestResultKey)
        } else {
            userDefaults.removeObject(forKey: connectionTestResultKey)
        }
        if let lastConnectionTestedAt = settings.lastConnectionTestedAt {
            userDefaults.set(lastConnectionTestedAt, forKey: connectionTestedAtKey)
        } else {
            userDefaults.removeObject(forKey: connectionTestedAtKey)
        }
        currentSettings = settings
    }

    private func readSettings() -> GitLabSettings {
        GitLabSettings(
            gitLabURL: userDefaults.string(forKey: gitLabURLKey) ?? "",
            personalAccessToken: (try? tokenStore.readToken()) ?? "",
            lastConnectionTestResult: readConnectionTestResult(),
            lastConnectionTestedAt: userDefaults.object(forKey: connectionTestedAtKey) as? Date
        )
    }

    private func readConnectionTestResult() -> GitLabConnectionTestResult? {
        guard let rawValue = userDefaults.string(forKey: connectionTestResultKey) else {
            return nil
        }

        return GitLabConnectionTestResult(rawValue: rawValue)
    }

    private static func defaultTokenStore() -> any GitLabTokenStoring {
        #if DEBUG
        return LocalGitLabTokenStore.default
        #else
        return KeychainTokenStore(
            service: "OpsHub.GitLab",
            account: "PersonalAccessToken"
        )
        #endif
    }
}

/// Token persistence abstraction used by GitLab settings and tests.
protocol GitLabTokenStoring {
    func readToken() throws -> String
    func saveToken(_ token: String) throws
}

/// Local file-backed storage used by development builds to avoid Keychain prompts while iterating.
final class LocalGitLabTokenStore: GitLabTokenStoring {
    static var `default`: LocalGitLabTokenStore {
        LocalGitLabTokenStore(
            tokenFileURL: FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("OpsHub", isDirectory: true)
                .appendingPathComponent("GitLab", isDirectory: true)
                .appendingPathComponent("personal-access-token")
        )
    }

    private let tokenFileURL: URL
    private let fileManager: FileManager

    init(tokenFileURL: URL, fileManager: FileManager = .default) {
        self.tokenFileURL = tokenFileURL
        self.fileManager = fileManager
    }

    func readToken() throws -> String {
        guard fileManager.fileExists(atPath: tokenFileURL.path) else {
            return ""
        }

        let data = try Data(contentsOf: tokenFileURL)
        guard let token = String(data: data, encoding: .utf8) else {
            throw GitLabSettingsStoreError.invalidTokenData
        }

        return token
    }

    func saveToken(_ token: String) throws {
        if token.isEmpty {
            try deleteToken()
            return
        }

        guard let data = token.data(using: .utf8) else {
            throw GitLabSettingsStoreError.invalidTokenData
        }

        try fileManager.createDirectory(
            at: tokenFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: tokenFileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: tokenFileURL.path
        )
    }

    private func deleteToken() throws {
        guard fileManager.fileExists(atPath: tokenFileURL.path) else {
            return
        }

        try fileManager.removeItem(at: tokenFileURL)
    }
}

/// Keychain-backed storage for the GitLab personal access token.
final class KeychainTokenStore: GitLabTokenStoring {
    private let service: String
    private let account: String
    private let accessible: CFString

    init(
        service: String,
        account: String,
        accessible: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    ) {
        self.service = service
        self.account = account
        self.accessible = accessible
    }

    func readToken() throws -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return ""
        }

        guard status == errSecSuccess else {
            throw GitLabSettingsStoreError.keychain(status)
        }

        guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
            throw GitLabSettingsStoreError.invalidTokenData
        }

        return token
    }

    func saveToken(_ token: String) throws {
        if token.isEmpty {
            try deleteToken()
            return
        }

        guard let data = token.data(using: .utf8) else {
            throw GitLabSettingsStoreError.invalidTokenData
        }

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecSuccess {
            return
        }

        guard updateStatus == errSecItemNotFound else {
            throw GitLabSettingsStoreError.keychain(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = accessible

        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw GitLabSettingsStoreError.keychain(addStatus)
        }
    }

    private func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw GitLabSettingsStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}

/// Errors that can occur while reading or writing GitLab settings.
enum GitLabSettingsStoreError: LocalizedError, Equatable {
    case invalidTokenData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidTokenData:
            return "The personal access token could not be encoded for secure storage."
        case let .keychain(status):
            return "Keychain could not save GitLab settings (status \(status))."
        }
    }
}
