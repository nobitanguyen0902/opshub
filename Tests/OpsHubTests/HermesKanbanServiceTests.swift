import XCTest
@testable import OpsHub

final class HermesKanbanServiceTests: XCTestCase {
    func testCreateUsesArgumentArrayAndJSON() async throws {
        let runner = RecordingShellRunner(responses: [
            ["kanban", "create", "Fix 'quoted' path", "--body", "Objective\nCriteria", "--assignee", "architect", "--workspace", "dir:/tmp/project path", "--priority", "2", "--idempotency-key", "opshub:workflow:architect:0", "--created-by", "opshub", "--json"]: .success(stdout: TaskFixture.createdJSON)
        ])
        let service = HermesKanbanService(runner: runner)

        let task = try await service.createTask(.init(
            title: "Fix 'quoted' path",
            body: "Objective\nCriteria",
            assignee: "architect",
            workspacePath: "/tmp/project path",
            priority: 2,
            idempotencyKey: "opshub:workflow:architect:0"
        ))

        XCTAssertEqual(task.id, "t_1")
        let arguments = await runner.lastArguments
        XCTAssertEqual(arguments, [
            "kanban", "create", "Fix 'quoted' path",
            "--body", "Objective\nCriteria",
            "--assignee", "architect",
            "--workspace", "dir:/tmp/project path",
            "--priority", "2",
            "--idempotency-key", "opshub:workflow:architect:0",
            "--created-by", "opshub",
            "--json"
        ])
    }

    func testReadCommandsDecodeTypedJSONAndUseArguments() async throws {
        do {
            _ = try JSONDecoder().decode(HermesKanbanTaskDetail.self, from: Data(TaskFixture.detailJSON.utf8))
        } catch {
            XCTFail("Fixture must decode directly: \(error)")
        }
        let runner = RecordingShellRunner(responses: [
            ["kanban", "list", "--json"]: .success(stdout: "[\(TaskFixture.taskJSON)]"),
            ["kanban", "show", "t_1", "--json"]: .success(stdout: TaskFixture.detailJSON),
            ["kanban", "runs", "t_1", "--json"]: .success(stdout: "[\(TaskFixture.runJSON)]")
        ])
        let service = HermesKanbanService(runner: runner)

        let tasks = try await service.listTasks()
        let detail = try await service.taskDetail(id: "t_1")
        let runs = try await service.runs(taskID: "t_1")

        XCTAssertEqual(tasks.map(\.status), [.review])
        XCTAssertEqual(detail.latestSummary, "Review ready")
        XCTAssertEqual(detail.parents, ["parent_1"])
        XCTAssertEqual(detail.children, ["child_1"])
        XCTAssertEqual(detail.comments.first?.author, "reviewer")
        XCTAssertEqual(detail.events.first?.runID, 7)
        XCTAssertEqual(runs.first?.metadata?.changedFiles, ["Sources/OpsHub/App.swift"])
        XCTAssertEqual(detail.runs[1].metadata?.risks, ["Needs approval"])
        XCTAssertEqual(detail.runs[2].metadata?.findings, [])
        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [
            ["kanban", "list", "--json"],
            ["kanban", "show", "t_1", "--json"],
            ["kanban", "runs", "t_1", "--json"]
        ])
    }

    func testLogClampsTailBytesAndReturnsDisplayTextOnly() async throws {
        let runner = RecordingShellRunner(responses: [
            ["kanban", "log", "t_1", "--tail", "1"]: .success(stdout: "human readable log\n")
        ])
        let service = HermesKanbanService(runner: runner)

        let log = try await service.log(taskID: "t_1", tailBytes: 0)
        XCTAssertEqual(log, "human readable log\n")
        let arguments = await runner.lastArguments
        XCTAssertEqual(arguments, ["kanban", "log", "t_1", "--tail", "1"])
    }

    func testLogCapsTailBytesAtOneMillion() async throws {
        let runner = RecordingShellRunner(responses: [
            ["kanban", "log", "t_1", "--tail", "1000000"]: .success(stdout: "log")
        ])
        let service = HermesKanbanService(runner: runner)

        _ = try await service.log(taskID: "t_1", tailBytes: 9_999_999)

        let arguments = await runner.lastArguments
        XCTAssertEqual(arguments, ["kanban", "log", "t_1", "--tail", "1000000"])
    }

    func testMutationCommandsUseExpectedArguments() async throws {
        let runner = RecordingShellRunner()
        let service = HermesKanbanService(runner: runner)

        try await service.reclaim(taskID: "t_1", reason: "Retry after review")
        try await service.block(taskID: "t_1", reason: "Need approval")
        try await service.unblock(taskID: "t_1", reason: "Approved")

        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [
            ["kanban", "reclaim", "t_1", "--reason", "Retry after review"],
            ["kanban", "block", "t_1", "--kind", "needs_input", "Need approval"],
            ["kanban", "unblock", "t_1", "--reason", "Approved"]
        ])
    }

    func testMalformedJSONMapsToKanbanIncompatibleJSONError() async {
        let runner = RecordingShellRunner(responses: [
            ["kanban", "list", "--json"]: .success(stdout: "not json")
        ])
        let service = HermesKanbanService(runner: runner)

        await XCTAssertThrowsErrorAsync(try await service.listTasks()) { error in
            XCTAssertEqual(error as? KanbanCommandError, .incompatibleJSON(command: "hermes kanban list --json"))
        }
    }

    func testNonzeroExitAndShellErrorsMapToKanbanErrors() async {
        let nonzeroRunner = RecordingShellRunner(responses: [
            ["kanban", "list", "--json"]: .result(stdout: "", stderr: "bad request", exitCode: 2)
        ])
        let service = HermesKanbanService(runner: nonzeroRunner)

        await XCTAssertThrowsErrorAsync(try await service.listTasks()) { error in
            XCTAssertEqual(error as? KanbanCommandError, .failed(command: "hermes kanban list --json", exitCode: 2, stderr: "bad request"))
        }

        for (shellError, expected) in [
            (ShellCommandError.permissionDenied(.init(stdout: "", stderr: "denied", exitCode: 126, duration: 0)), KanbanCommandError.permissionDenied(command: "hermes kanban list --json")),
            (ShellCommandError.timedOut(.init(stdout: "", stderr: "slow", exitCode: 15, duration: 0)), KanbanCommandError.timedOut(command: "hermes kanban list --json")),
            (ShellCommandError.commandFailed(.init(stdout: "", stderr: "failed", exitCode: 1, duration: 0)), KanbanCommandError.failed(command: "hermes kanban list --json", exitCode: 1, stderr: "failed")),
            (ShellCommandError.launchFailed(TestLaunchError()), KanbanCommandError.launch("runner unavailable"))
        ] {
            let throwingRunner = ThrowingShellRunner(error: shellError)
            await XCTAssertThrowsErrorAsync(try await HermesKanbanService(runner: throwingRunner).listTasks()) { error in
                XCTAssertEqual(error as? KanbanCommandError, expected)
            }
        }
    }

    func testFailedCreateRedactsTitleBodyAndWorkspacePathFromError() async {
        let title = "Confidential project launch"
        let body = "Secret objective and acceptance criteria"
        let workspacePath = "/private/secret customer/project"
        let runner = RecordingShellRunner(responses: [
            ["kanban", "create", title, "--body", body, "--assignee", "architect", "--workspace", "dir:\(workspacePath)", "--priority", "2", "--idempotency-key", "key", "--created-by", "opshub", "--json"]: .result(stdout: "", stderr: "request failed", exitCode: 1)
        ])
        let service = HermesKanbanService(runner: runner)

        await XCTAssertThrowsErrorAsync(try await service.createTask(.init(
            title: title,
            body: body,
            assignee: "architect",
            workspacePath: workspacePath,
            priority: 2,
            idempotencyKey: "key"
        ))) { error in
            let description = error.localizedDescription
            XCTAssertEqual(error as? KanbanCommandError, .failed(command: "hermes kanban create <redacted>", exitCode: 1, stderr: "request failed"))
            XCTAssertFalse(description.contains(title))
            XCTAssertFalse(description.contains(body))
            XCTAssertFalse(description.contains(workspacePath))
        }
    }

    func testCapabilitiesDependOnlyOnCommandSuccess() async {
        let runner = RecordingShellRunner(responses: [
            ["--version"]: .success(stdout: "Hermes 1.0"),
            ["profile", "show", "architect"]: .result(stdout: "", stderr: "not found", exitCode: 1),
            ["gateway", "status"]: .success(stdout: "stopped")
        ])
        let service = HermesKanbanService(runner: runner)

        let isAvailable = await service.isAvailable()
        let profileExists = await service.profileExists("architect")
        let isGatewayRunning = await service.isGatewayRunning()
        XCTAssertTrue(isAvailable)
        XCTAssertFalse(profileExists)
        XCTAssertTrue(isGatewayRunning)
    }
}

private actor RecordingShellRunner: ShellCommandRunning {
    enum Response: Sendable {
        case success(stdout: String)
        case result(stdout: String, stderr: String, exitCode: Int32)
    }

    private let responses: [[String]: Response]
    private(set) var arguments: [[String]] = []
    var lastArguments: [String] { arguments.last ?? [] }

    init(responses: [[String]: Response] = [:]) {
        self.responses = responses
    }

    func run(_ command: String) async throws -> ShellCommandResult {
        try await run(command, arguments: [])
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        self.arguments.append(arguments)
        switch responses[arguments] ?? .success(stdout: "") {
        case let .success(stdout):
            return .init(stdout: stdout, stderr: "", exitCode: 0, duration: 0)
        case let .result(stdout, stderr, exitCode):
            return .init(stdout: stdout, stderr: stderr, exitCode: exitCode, duration: 0)
        }
    }
}

private struct ThrowingShellRunner: ShellCommandRunning {
    let error: Error

    func run(_ command: String) async throws -> ShellCommandResult { throw error }
    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult { throw error }
}

private struct TestLaunchError: LocalizedError {
    var errorDescription: String? { "runner unavailable" }
}

private enum TaskFixture {
    static let taskJSON = #"{"id":"t_1","title":"Fix quoted path","body":"Objective","assignee":"architect","status":"review","priority":2,"tenant":null,"workspace_kind":"dir","workspace_path":"/tmp/project","branch_name":null,"project_id":null,"created_by":"opshub","created_at":1,"started_at":2,"completed_at":null,"result":null}"#

    static let createdJSON = #"{"id":"t_1","title":"Fix 'quoted' path","body":"Objective\nCriteria","assignee":"architect","status":"ready","priority":2,"tenant":null,"workspace_kind":"dir","workspace_path":"/tmp/project path","branch_name":null,"project_id":null,"created_by":"opshub","created_at":1,"started_at":null,"completed_at":null,"result":null}"#

    static let runJSON = #"{"id":7,"profile":"developer","step_key":"implement","status":"completed","outcome":"completed","summary":"Implemented","error":null,"metadata":{"schemaVersion":1,"outcome":"completed","summary":"Implemented","risks":[],"changedFiles":["Sources/OpsHub/App.swift"],"verification":["swift test"],"findings":null},"worker_pid":123,"started_at":2,"ended_at":3}"#

    static let architectRunJSON = #"{"id":8,"profile":"architect","step_key":"design","status":"completed","outcome":"ready","summary":"Designed","error":null,"metadata":{"schemaVersion":1,"outcome":"ready","summary":"Designed","risks":["Needs approval"],"changedFiles":null,"verification":null,"findings":null},"worker_pid":124,"started_at":3,"ended_at":4}"#

    static let reviewerRunJSON = #"{"id":9,"profile":"reviewer","step_key":"review","status":"completed","outcome":"approved","summary":"Approved","error":null,"metadata":{"schemaVersion":1,"outcome":"approved","summary":"Approved","risks":null,"changedFiles":null,"verification":null,"findings":[]},"worker_pid":125,"started_at":4,"ended_at":5}"#

    static let detailJSON = #"{"task":\#(taskJSON),"latest_summary":"Review ready","parents":["parent_1"],"children":["child_1"],"comments":[{"author":"reviewer","body":"Looks good","created_at":4}],"events":[{"kind":"completed","payload":"{}","created_at":5,"run_id":7}],"runs":[\#(runJSON),\#(architectRunJSON),\#(reviewerRunJSON)]}"#
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown")
    } catch {
        errorHandler(error)
    }
}
