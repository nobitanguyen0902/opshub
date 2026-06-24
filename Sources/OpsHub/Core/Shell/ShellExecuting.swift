import Foundation

protocol ShellExecuting: Sendable {
    func run(_ command: String, arguments: [String]) async throws -> String
}

struct ShellExecutor: ShellExecuting {
    func run(_ command: String, arguments: [String]) async throws -> String {
        let process = Process()
        let output = Pipe()

        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let result = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw ShellError.commandFailed(result)
        }
        return result
    }
}

enum ShellError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(message):
            message
        }
    }
}
