import Darwin
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
        let execution = ShellCommandExecution()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try Self.executeSynchronously(
                            command,
                            timeout: timeout,
                            execution: execution
                        )
                    })
                }
            }
        } onCancel: {
            execution.requestStop(.cancelled)
        }
    }

    private static func executeSynchronously(
        _ command: String,
        timeout: TimeInterval,
        execution: ShellCommandExecution
    ) throws -> ShellCommandResult {
        guard execution.canLaunch else { throw CancellationError() }

        let stdout = Pipe()
        let stderr = Pipe()
        let stdoutCollector = PipeOutputCollector()
        let stderrCollector = PipeOutputCollector()
        let outputDrains = DispatchGroup()
        let stdoutDrain = PipeOutputDrain(
            handle: stdout.fileHandleForReading,
            collector: stdoutCollector,
            group: outputDrains
        )
        let stderrDrain = PipeOutputDrain(
            handle: stderr.fileHandleForReading,
            collector: stderrCollector,
            group: outputDrains
        )
        let start = Date()

        let processID: pid_t
        do {
            processID = try spawn(
                command,
                stdoutFileDescriptor: stdout.fileHandleForWriting.fileDescriptor,
                stderrFileDescriptor: stderr.fileHandleForWriting.fileDescriptor,
                descriptorsToClose: [
                    stdout.fileHandleForReading.fileDescriptor,
                    stderr.fileHandleForReading.fileDescriptor
                ]
            )
        } catch {
            stdout.fileHandleForWriting.closeFile()
            stderr.fileHandleForWriting.closeFile()
            stdoutDrain.forceFinish()
            stderrDrain.forceFinish()
            if execution.stopReason == .cancelled {
                throw CancellationError()
            }
            throw ShellCommandError.launchFailed(error)
        }

        stdout.fileHandleForWriting.closeFile()
        stderr.fileHandleForWriting.closeFile()
        execution.didLaunch(
            processID: processID,
            drains: [stdoutDrain, stderrDrain]
        )

        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .userInitiated))
        timer.schedule(deadline: .now() + timeout)
        timer.setEventHandler {
            execution.requestStop(.timedOut)
        }
        timer.resume()

        // Keep the group leader unreaped until every inherited output descriptor
        // has closed. This makes the process-group ID ineligible for reuse while
        // timeout or cancellation cleanup may still need to signal descendants.
        outputDrains.wait()
        let exitCode = waitForExit(of: processID)
        let stopReason = execution.complete()
        timer.cancel()

        let result = ShellCommandResult(
            stdout: String(decoding: stdoutCollector.data, as: UTF8.self),
            stderr: String(decoding: stderrCollector.data, as: UTF8.self),
            exitCode: exitCode,
            duration: Date().timeIntervalSince(start)
        )

        switch stopReason {
        case .cancelled:
            throw CancellationError()
        case .timedOut:
            throw ShellCommandError.timedOut(result)
        case nil:
            if result.exitCode == 0 {
                return result
            } else if isPermissionDenied(result) {
                throw ShellCommandError.permissionDenied(result)
            } else {
                throw ShellCommandError.commandFailed(result)
            }
        }
    }

    private static func spawn(
        _ command: String,
        stdoutFileDescriptor: Int32,
        stderrFileDescriptor: Int32,
        descriptorsToClose: [Int32]
    ) throws -> pid_t {
        var fileActions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try checkPOSIX(posix_spawn_file_actions_init(&fileActions))
        defer { posix_spawn_file_actions_destroy(&fileActions) }
        try checkPOSIX(posix_spawnattr_init(&attributes))
        defer {
            posix_spawnattr_destroy(&attributes)
        }

        try checkPOSIX(posix_spawn_file_actions_adddup2(&fileActions, stdoutFileDescriptor, STDOUT_FILENO))
        try checkPOSIX(posix_spawn_file_actions_adddup2(&fileActions, stderrFileDescriptor, STDERR_FILENO))
        for descriptor in descriptorsToClose {
            try checkPOSIX(posix_spawn_file_actions_addclose(&fileActions, descriptor))
        }
        if stdoutFileDescriptor != STDOUT_FILENO {
            try checkPOSIX(posix_spawn_file_actions_addclose(&fileActions, stdoutFileDescriptor))
        }
        if stderrFileDescriptor != STDERR_FILENO {
            try checkPOSIX(posix_spawn_file_actions_addclose(&fileActions, stderrFileDescriptor))
        }

        let flags = Int16(POSIX_SPAWN_SETPGROUP)
        try checkPOSIX(posix_spawnattr_setflags(&attributes, flags))
        try checkPOSIX(posix_spawnattr_setpgroup(&attributes, 0))

        let arguments = ["/bin/zsh", "-lc", command]
        var duplicatedArguments = arguments.map { strdup($0) } + [nil]
        defer {
            for case let pointer? in duplicatedArguments {
                free(UnsafeMutableRawPointer(pointer))
            }
        }
        var duplicatedEnvironment = ProcessInfo.processInfo.environment
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for case let pointer? in duplicatedEnvironment {
                free(UnsafeMutableRawPointer(pointer))
            }
        }

        var processID: pid_t = 0
        let launchResult = duplicatedArguments.withUnsafeMutableBufferPointer { argumentsBuffer in
            duplicatedEnvironment.withUnsafeMutableBufferPointer { environmentBuffer in
                posix_spawn(
                    &processID,
                    "/bin/zsh",
                    &fileActions,
                    &attributes,
                    argumentsBuffer.baseAddress!,
                    environmentBuffer.baseAddress!
                )
            }
        }
        guard launchResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(launchResult))
        }
        return processID
    }

    private static func checkPOSIX(_ result: Int32) throws {
        guard result == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(result))
        }
    }

    private static func waitForExit(of processID: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(processID, &status, 0) == -1 {
            if errno != EINTR {
                return -1
            }
        }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : signal
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

private enum ShellCommandStopReason: Equatable {
    case timedOut
    case cancelled
}

private final class ShellCommandExecution: @unchecked Sendable {
    private static let terminationGrace: TimeInterval = 0.2
    private static let drainGrace: TimeInterval = 0.5

    private let lock = NSLock()
    private var processID: pid_t?
    private var drains: [PipeOutputDrain] = []
    private var reason: ShellCommandStopReason?
    private var isComplete = false

    var canLaunch: Bool {
        lock.withLock { reason == nil && !isComplete }
    }

    var stopReason: ShellCommandStopReason? {
        lock.withLock { reason }
    }

    func didLaunch(processID: pid_t, drains: [PipeOutputDrain]) {
        let shouldStop = lock.withLock {
            self.processID = processID
            self.drains = drains
            return reason != nil && !isComplete
        }
        if shouldStop {
            terminate(processID: processID, drains: drains)
        }
    }

    func requestStop(_ requestedReason: ShellCommandStopReason) {
        let target = lock.withLock { () -> (pid_t, [PipeOutputDrain])? in
            guard !isComplete else { return nil }
            if reason == nil {
                reason = requestedReason
            }
            guard let processID else { return nil }
            return (processID, drains)
        }
        if let target {
            terminate(processID: target.0, drains: target.1)
        }
    }

    func complete() -> ShellCommandStopReason? {
        lock.withLock {
            isComplete = true
            processID = nil
            drains = []
            return reason
        }
    }

    private func terminate(processID: pid_t, drains: [PipeOutputDrain]) {
        signalGroup(processID, signal: SIGTERM)
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.terminationGrace) { [weak self] in
            guard self?.isActive(processID: processID) == true else { return }
            self?.signalGroup(processID, signal: SIGKILL)
        }
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Self.drainGrace) { [weak self] in
            guard self?.isActive(processID: processID) == true else { return }
            drains.forEach { $0.forceFinish() }
        }
    }

    private func isActive(processID: pid_t) -> Bool {
        lock.withLock { !isComplete && self.processID == processID }
    }

    private func signalGroup(_ processID: pid_t, signal: Int32) {
        // The group was created atomically by POSIX_SPAWN_SETPGROUP, so this
        // negative PID cannot target OpsHub's own or another pre-existing group.
        _ = Darwin.kill(-processID, signal)
    }
}

private final class PipeOutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()

    var data: Data {
        lock.withLock { buffer }
    }

    func append(_ data: Data) {
        lock.withLock { buffer.append(data) }
    }
}

private final class PipeOutputDrain: @unchecked Sendable {
    private let lock = NSLock()
    private let handle: FileHandle
    private let collector: PipeOutputCollector
    private let group: DispatchGroup
    private var isFinished = false

    init(handle: FileHandle, collector: PipeOutputCollector, group: DispatchGroup) {
        self.handle = handle
        self.collector = collector
        self.group = group
        group.enter()
        handle.readabilityHandler = { [weak self] readableHandle in
            self?.consume(from: readableHandle)
        }
    }

    func forceFinish() {
        finish(closeHandle: true)
    }

    private func consume(from readableHandle: FileHandle) {
        let data = readableHandle.availableData
        if data.isEmpty {
            finish(closeHandle: false)
        } else {
            collector.append(data)
        }
    }

    private func finish(closeHandle: Bool) {
        let shouldFinish = lock.withLock {
            guard !isFinished else { return false }
            isFinished = true
            return true
        }
        guard shouldFinish else { return }
        handle.readabilityHandler = nil
        if closeHandle {
            handle.closeFile()
        }
        group.leave()
    }
}
