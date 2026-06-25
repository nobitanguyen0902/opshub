import Foundation
import Security

/// Stores non-secret GitLab settings in UserDefaults and the token in Keychain.
final class GitLabSettingsStore: GitLabSettingsStoring {
    private let userDefaults: UserDefaults
    private let keychainTokenStore: any KeychainTokenStoring
    private let gitLabURLKey: String
    private var currentSettings: GitLabSettings

    init(
        userDefaults: UserDefaults = .standard,
        keychainTokenStore: any KeychainTokenStoring = KeychainTokenStore(
            service: "OpsHub.GitLab",
            account: "PersonalAccessToken"
        ),
        gitLabURLKey: String = "gitlab.url"
    ) {
        self.userDefaults = userDefaults
        self.keychainTokenStore = keychainTokenStore
        self.gitLabURLKey = gitLabURLKey
        currentSettings = GitLabSettings(gitLabURL: "", personalAccessToken: "")
        currentSettings = readSettings()
    }

    func load() -> GitLabSettings {
        currentSettings
    }

    func save(_ settings: GitLabSettings) throws {
        userDefaults.set(settings.gitLabURL, forKey: gitLabURLKey)
        try keychainTokenStore.saveToken(settings.personalAccessToken)
        currentSettings = settings
    }

    private func readSettings() -> GitLabSettings {
        GitLabSettings(
            gitLabURL: userDefaults.string(forKey: gitLabURLKey) ?? "",
            personalAccessToken: (try? keychainTokenStore.readToken()) ?? ""
        )
    }
}

/// Keychain abstraction used by GitLab settings persistence and tests.
protocol KeychainTokenStoring {
    func readToken() throws -> String
    func saveToken(_ token: String) throws
}

/// Keychain-backed storage for the GitLab personal access token.
final class KeychainTokenStore: KeychainTokenStoring {
    private let service: String
    private let account: String

    init(service: String, account: String) {
        self.service = service
        self.account = account
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

        try deleteToken()

        var item = baseQuery
        item[kSecValueData as String] = data

        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw GitLabSettingsStoreError.keychain(status)
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
            kSecAttrAccount as String: account
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
