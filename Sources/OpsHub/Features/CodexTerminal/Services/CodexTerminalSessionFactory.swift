import Foundation

@MainActor
protocol CodexTerminalSessionCreating {
    func makeSession(title: String, startDirectory: URL) throws -> CodexTerminalSession
}

@MainActor
final class CodexTerminalSessionFactory: CodexTerminalSessionCreating {
    private let configuration: CodexLaunchConfiguration

    init(configuration: CodexLaunchConfiguration = CodexLaunchConfiguration()) {
        self.configuration = configuration
    }

    func makeSession(title: String, startDirectory: URL) throws -> CodexTerminalSession {
        let host = SwiftTermCodexTerminalHost(startDirectory: startDirectory, configuration: configuration)
        return CodexTerminalSession(title: title, host: host)
    }
}