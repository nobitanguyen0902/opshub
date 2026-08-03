import Foundation

protocol HermesKanbanServicing: Sendable {
    func listTasks() async throws -> [HermesKanbanTask]
    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail
    func runs(taskID: String) async throws -> [HermesKanbanRun]
    func log(taskID: String, tailBytes: Int) async throws -> String
    func isAvailable() async -> Bool
    func profileExists(_ profile: String) async -> Bool
    func isGatewayRunning() async -> Bool
    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask
    func reclaim(taskID: String, reason: String) async throws
    func block(taskID: String, reason: String) async throws
    func unblock(taskID: String, reason: String) async throws
}

struct HermesTaskCreateRequest: Equatable, Sendable {
    let title: String
    let body: String
    let assignee: String
    let workspacePath: String
    let priority: Int
    let idempotencyKey: String
}

enum KanbanCommandError: LocalizedError, Equatable {
    case launch(String)
    case permissionDenied(command: String)
    case timedOut(command: String)
    case failed(command: String, exitCode: Int32, stderr: String)
    case incompatibleJSON(command: String)

    var errorDescription: String? {
        switch self {
        case let .launch(message):
            "Unable to start Hermes: \(message)"
        case let .permissionDenied(command):
            "Hermes does not have permission to run \(command)."
        case let .timedOut(command):
            "Hermes timed out while running \(command)."
        case let .failed(command, exitCode, _):
            "Hermes command failed (exit code \(exitCode)): \(command)."
        case let .incompatibleJSON(command):
            "Hermes returned Kanban data the app could not read: \(command)."
        }
    }
}

struct HermesKanbanService: HermesKanbanServicing {
    private let runner: any ShellCommandRunning
    private let decoder = JSONDecoder()

    init(runner: any ShellCommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    func listTasks() async throws -> [HermesKanbanTask] {
        try await decode([HermesKanbanTask].self, arguments: ["kanban", "list", "--json"])
    }

    func taskDetail(id: String) async throws -> HermesKanbanTaskDetail {
        try await decode(HermesKanbanTaskDetail.self, arguments: ["kanban", "show", id, "--json"])
    }

    func runs(taskID: String) async throws -> [HermesKanbanRun] {
        try await decode([HermesKanbanRun].self, arguments: ["kanban", "runs", taskID, "--json"])
    }

    func log(taskID: String, tailBytes: Int) async throws -> String {
        let safeTailBytes = min(max(tailBytes, 1), 1_000_000)
        return try await run(["kanban", "log", taskID, "--tail", String(safeTailBytes)]).stdout
    }

    func isAvailable() async -> Bool {
        await commandSucceeds(["--version"])
    }

    func profileExists(_ profile: String) async -> Bool {
        await commandSucceeds(["profile", "show", profile])
    }

    func isGatewayRunning() async -> Bool {
        await commandSucceeds(["gateway", "status"])
    }

    func createTask(_ request: HermesTaskCreateRequest) async throws -> HermesKanbanTask {
        try await decode(HermesKanbanTask.self, arguments: [
            "kanban", "create", request.title,
            "--body", request.body,
            "--assignee", request.assignee,
            "--workspace", "dir:\(request.workspacePath)",
            "--priority", String(request.priority),
            "--idempotency-key", request.idempotencyKey,
            "--created-by", "opshub",
            "--json"
        ])
    }

    func reclaim(taskID: String, reason: String) async throws {
        _ = try await run(["kanban", "reclaim", taskID, "--reason", reason])
    }

    func block(taskID: String, reason: String) async throws {
        _ = try await run(["kanban", "block", taskID, "--kind", "needs_input", reason])
    }

    func unblock(taskID: String, reason: String) async throws {
        _ = try await run(["kanban", "unblock", taskID, "--reason", reason])
    }

    private func commandSucceeds(_ arguments: [String]) async -> Bool {
        do {
            return try await runner.run("hermes", arguments: arguments).exitCode == 0
        } catch {
            return false
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, arguments: [String]) async throws -> T {
        let command = commandDescription(arguments)
        let result = try await run(arguments)
        do {
            return try decoder.decode(T.self, from: Data(result.stdout.utf8))
        } catch {
            throw KanbanCommandError.incompatibleJSON(command: command)
        }
    }

    private func run(_ arguments: [String]) async throws -> ShellCommandResult {
        let command = commandDescription(arguments)
        do {
            let result = try await runner.run("hermes", arguments: arguments)
            guard result.exitCode == 0 else {
                throw KanbanCommandError.failed(command: command, exitCode: result.exitCode, stderr: result.stderr)
            }
            return result
        } catch let error as KanbanCommandError {
            throw error
        } catch let error as ShellCommandError {
            switch error {
            case let .commandFailed(result):
                throw KanbanCommandError.failed(command: command, exitCode: result.exitCode, stderr: result.stderr)
            case .permissionDenied:
                throw KanbanCommandError.permissionDenied(command: command)
            case .timedOut:
                throw KanbanCommandError.timedOut(command: command)
            case let .launchFailed(error):
                throw KanbanCommandError.launch(error.localizedDescription)
            }
        } catch {
            throw KanbanCommandError.launch(error.localizedDescription)
        }
    }

    private func commandDescription(_ arguments: [String]) -> String {
        guard arguments.first == "kanban", let action = arguments.dropFirst().first else {
            return "hermes"
        }

        switch action {
        case "list":
            return "hermes kanban list --json"
        case "show":
            return "hermes kanban show <task-id> --json"
        case "runs":
            return "hermes kanban runs <task-id> --json"
        case "log":
            return "hermes kanban log <task-id> --tail <bytes>"
        case "create", "reclaim", "block", "unblock":
            return "hermes kanban \(action) <redacted>"
        default:
            return "hermes kanban \(action)"
        }
    }
}
