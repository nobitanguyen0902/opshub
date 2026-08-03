import Foundation
import XCTest
@testable import OpsHub

final class KanbanWorkspaceValidatorTests: XCTestCase {
    func testDraftValidationRejectsMissingDirectory() async throws {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-repo-\(UUID().uuidString)")
        let validator = KanbanWorkspaceValidator(runner: WorkspaceRunner())

        await XCTAssertThrowsErrorAsync(try await validator.validateDraftPath(missingURL)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .missingDirectory)
        }
    }

    func testDraftValidationRejectsNonGitDirectory() async throws {
        let directoryURL = try makeDirectory(named: "not-a-repo")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let failure = ShellCommandResult(stdout: "", stderr: "not a git repository", exitCode: 128, duration: 0)
        let validator = KanbanWorkspaceValidator(
            runner: WorkspaceRunner(results: [.failure(.commandFailed(failure))])
        )

        await XCTAssertThrowsErrorAsync(try await validator.validateDraftPath(directoryURL)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .notGitRepository)
        }
    }

    func testDraftValidationRejectsNestedRepositoryDirectory() async throws {
        let rootURL = try makeDirectory(named: "repo-root")
        let nestedURL = rootURL.appendingPathComponent("Sources", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }
        let validator = KanbanWorkspaceValidator(
            runner: WorkspaceRunner(results: [
                .success(.init(stdout: rootURL.path + "\n", stderr: "", exitCode: 0, duration: 0))
            ])
        )

        await XCTAssertThrowsErrorAsync(try await validator.validateDraftPath(nestedURL)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .notRepositoryRoot)
        }
    }

    func testDraftValidationResolvesRepositoryRootSymlink() async throws {
        let rootURL = try makeDirectory(named: "repo-root")
        let symlinkURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-link-\(UUID().uuidString)")
        try FileManager.default.createSymbolicLink(at: symlinkURL, withDestinationURL: rootURL)
        defer {
            try? FileManager.default.removeItem(at: symlinkURL)
            try? FileManager.default.removeItem(at: rootURL)
        }
        let validator = KanbanWorkspaceValidator(
            runner: WorkspaceRunner(results: [
                .success(.init(stdout: rootURL.path + "\n", stderr: "", exitCode: 0, duration: 0))
            ])
        )

        let validatedURL = try await validator.validateDraftPath(symlinkURL)

        XCTAssertEqual(validatedURL, rootURL.standardizedFileURL.resolvingSymlinksInPath())
    }

    func testStartRejectsDirtyWorkingTree() async throws {
        let directoryURL = try makeDirectory(named: "repo")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let runner = WorkspaceRunner(results: [
            .success(.init(stdout: directoryURL.path + "\n", stderr: "", exitCode: 0, duration: 0)),
            .success(.init(stdout: " M Sources/File.swift\n", stderr: "", exitCode: 0, duration: 0))
        ])
        let validator = KanbanWorkspaceValidator(runner: runner)

        await XCTAssertThrowsErrorAsync(try await validator.validateStart(directoryURL)) { error in
            XCTAssertEqual(error as? KanbanStartGuardError, .dirtyWorkingTree([" M Sources/File.swift"]))
        }
    }

    func testStartReturnsCanonicalRootForCleanWorkingTree() async throws {
        let directoryURL = try makeDirectory(named: "repo")
        defer { try? FileManager.default.removeItem(at: directoryURL) }
        let runner = WorkspaceRunner(results: [
            .success(.init(stdout: directoryURL.path + "\n", stderr: "", exitCode: 0, duration: 0)),
            .success(.init(stdout: "\n", stderr: "", exitCode: 0, duration: 0))
        ])
        let validator = KanbanWorkspaceValidator(runner: runner)

        let validatedURL = try await validator.validateStart(directoryURL)

        XCTAssertEqual(validatedURL, directoryURL.standardizedFileURL.resolvingSymlinksInPath())
    }

    private func makeDirectory(named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private actor WorkspaceRunner: ShellCommandRunning {
    private var results: [Result<ShellCommandResult, ShellCommandError>]

    init(results: [Result<ShellCommandResult, ShellCommandError>] = []) {
        self.results = results
    }

    func run(_ command: String) async throws -> ShellCommandResult {
        try await run(command, arguments: [])
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        guard !results.isEmpty else {
            return .init(stdout: "", stderr: "", exitCode: 0, duration: 0)
        }
        return try results.removeFirst().get()
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
