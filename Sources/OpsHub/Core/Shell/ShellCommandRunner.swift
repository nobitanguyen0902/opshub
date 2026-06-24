import Foundation

struct ShellCommandResult: Sendable, Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: TimeInterval
}

enum ShellCommandError: LocalizedError {
    case commandFailed(ShellCommandResult)
    case launchFailed(Error)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(result):
            let message = result.stderr.isEmpty ? result.stdout : result.stderr
            return message.isEmpty
                ? "Command failed with exit code \(result.exitCode)."
                : message
        case let .launchFailed(error):
            return error.localizedDescription
        }
    }
}

struct ShellCommandRunner: ShellCommandRunning {
    func run(_ command: String) async throws -> ShellCommandResult {
        try await execute(command)
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        try await execute(Self.makeCommand(command, arguments: arguments))
    }

    private func execute(_ command: String) async throws -> ShellCommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                let start = Date()

                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = ["-lc", command]
                process.standardOutput = stdout
                process.standardError = stderr

                do {
                    try process.run()
                    process.waitUntilExit()

                    let result = ShellCommandResult(
                        stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                        stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                        exitCode: process.terminationStatus,
                        duration: Date().timeIntervalSince(start)
                    )

                    if result.exitCode == 0 {
                        continuation.resume(returning: result)
                    } else {
                        continuation.resume(throwing: ShellCommandError.commandFailed(result))
                    }
                } catch {
                    continuation.resume(throwing: ShellCommandError.launchFailed(error))
                }
            }
        }
    }

    private static func makeCommand(_ command: String, arguments: [String]) -> String {
        ([command] + arguments)
            .map(shellEscape)
            .joined(separator: " ")
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }
}
