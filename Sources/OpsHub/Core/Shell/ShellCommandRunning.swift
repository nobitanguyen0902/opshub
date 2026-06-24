import Foundation

protocol ShellCommandRunning: Sendable {
    func run(_ command: String) async throws -> ShellCommandResult
    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult
}
