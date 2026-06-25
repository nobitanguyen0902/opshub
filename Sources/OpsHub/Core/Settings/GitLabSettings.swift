import Foundation

struct GitLabSettings: Equatable, Sendable {
    var gitLabURL: String
    var personalAccessToken: String
}

protocol GitLabSettingsStoring {
    func load() -> GitLabSettings
    func save(_ settings: GitLabSettings) throws
}
