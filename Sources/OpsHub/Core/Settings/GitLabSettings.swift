import Foundation

/// Persisted GitLab host and personal access token configuration.
struct GitLabSettings: Equatable, Sendable {
    var gitLabURL: String
    var personalAccessToken: String
}

/// Loads and saves GitLab settings across app launches.
protocol GitLabSettingsStoring {
    func load() -> GitLabSettings
    func save(_ settings: GitLabSettings) throws
}
