import Foundation

struct ShellCommandResult: Sendable, Equatable {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    let duration: TimeInterval
}

enum ShellCommandError: LocalizedError {
    case commandFailed(ShellCommandResult)
    case permissionDenied(ShellCommandResult)
    case timedOut(ShellCommandResult)
    case launchFailed(Error)

    var result: ShellCommandResult? {
        switch self {
        case let .commandFailed(result), let .permissionDenied(result), let .timedOut(result):
            result
        case .launchFailed:
            nil
        }
    }

    var errorDescription: String? {
        switch self {
        case let .commandFailed(result):
            return "Homebrew could not complete the command (exit code \(result.exitCode)). See Command Log for details."
        case .permissionDenied:
            return "Homebrew does not have permission to run this command. Check the command permissions and try again."
        case .timedOut:
            return "The Homebrew command took too long and was stopped. Please try again."
        case let .launchFailed(error):
            return "Unable to start the Homebrew command: \(error.localizedDescription)"
        }
    }
}

struct ShellCommandRunner: ShellCommandRunning {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 60) {
        self.timeout = timeout
    }

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

                    let timeoutState = TimeoutState()
                    let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
                    timer.schedule(deadline: .now() + self.timeout)
                    timer.setEventHandler {
                        guard process.isRunning else { return }
                        timeoutState.markTimedOut()
                        process.terminate()
                    }
                    timer.resume()
                    process.waitUntilExit()
                    timer.cancel()

                    let result = ShellCommandResult(
                        stdout: String(decoding: stdout.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                        stderr: String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
                        exitCode: process.terminationStatus,
                        duration: Date().timeIntervalSince(start)
                    )

                    if timeoutState.didTimeOut {
                        continuation.resume(throwing: ShellCommandError.timedOut(result))
                    } else if result.exitCode == 0 {
                        continuation.resume(returning: result)
                    } else if Self.isPermissionDenied(result) {
                        continuation.resume(throwing: ShellCommandError.permissionDenied(result))
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

    private static func isPermissionDenied(_ result: ShellCommandResult) -> Bool {
        let output = "\(result.stdout)\n\(result.stderr)".lowercased()
        return output.contains("permission denied") || output.contains("operation not permitted")
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }
}

private final class TimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var isTimedOut = false

    var didTimeOut: Bool {
        lock.withLock { isTimedOut }
    }

    func markTimedOut() {
        lock.withLock { isTimedOut = true }
    }
}
