import Foundation
import XCTest
@testable import OpsHub

@MainActor
final class CodexTerminalViewModelTests: XCTestCase {
    func testCreatesSelectsAndClosesIndependentSessions() throws {
        let factory = CodexTestSessionFactory()
        let viewModel = CodexTerminalViewModel(factory: factory)

        let first = try viewModel.createSession()
        let second = try viewModel.createSession()

        XCTAssertEqual(viewModel.sessions.map(\.title), ["Terminal 1", "Terminal 2"])
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(viewModel.selectedSessionID, second.id)
        XCTAssertEqual(factory.startDirectories, [
            FileManager.default.homeDirectoryForCurrentUser,
            FileManager.default.homeDirectoryForCurrentUser
        ])

        viewModel.select(first.id)
        XCTAssertEqual(viewModel.selectedSessionID, first.id)
        XCTAssertTrue(viewModel.requiresCloseConfirmation(first.id))
        viewModel.close(first.id)
        XCTAssertEqual(first.terminateCount, 1)
        XCTAssertEqual(viewModel.sessions.map(\.id), [second.id])
    }

    func testCleanupTerminatesOnlyActiveSessions() throws {
        let viewModel = CodexTerminalViewModel(factory: CodexTestSessionFactory())
        let active = try viewModel.createSession()
        let exited = try viewModel.createSession()
        exited.state = .exited(code: 0)

        viewModel.terminateAll()

        XCTAssertEqual(active.terminateCount, 1)
        XCTAssertEqual(exited.terminateCount, 0)
    }

    func testRenamesNonSelectedSessionWithoutAffectingSelectionOrHost() throws {
        let viewModel = CodexTerminalViewModel(factory: CodexTestSessionFactory())
        let first = try viewModel.createSession()
        let second = try viewModel.createSession()

        viewModel.renameSession(first.id, to: "Architect")

        XCTAssertEqual(first.title, "Architect")
        XCTAssertEqual(second.title, "Terminal 2")
        XCTAssertEqual(viewModel.selectedSessionID, second.id)
        XCTAssertEqual(first.terminateCount, 0)
        XCTAssertEqual(second.terminateCount, 0)
        XCTAssertEqual(first.state, .starting)
    }

    func testRenameTrimsWhitespaceAndRejectsBlankTitle() throws {
        let viewModel = CodexTerminalViewModel(factory: CodexTestSessionFactory())
        let session = try viewModel.createSession()

        viewModel.renameSession(session.id, to: "  Build Logs\n")
        XCTAssertEqual(session.title, "Build Logs")

        viewModel.renameSession(session.id, to: " \n\t ")
        XCTAssertEqual(session.title, "Build Logs")
    }

    func testRenameAllowsDuplicateTitles() throws {
        let viewModel = CodexTerminalViewModel(factory: CodexTestSessionFactory())
        let first = try viewModel.createSession()
        let second = try viewModel.createSession()

        viewModel.renameSession(first.id, to: "Shared")
        viewModel.renameSession(second.id, to: "Shared")

        XCTAssertEqual(viewModel.sessions.map(\.title), ["Shared", "Shared"])
    }

    func testRenameUnknownSessionDoesNotChangeExistingSessions() throws {
        let viewModel = CodexTerminalViewModel(factory: CodexTestSessionFactory())
        _ = try viewModel.createSession()
        _ = try viewModel.createSession()

        viewModel.renameSession(UUID(), to: "Unknown")

        XCTAssertEqual(viewModel.sessions.map(\.title), ["Terminal 1", "Terminal 2"])
    }
}

@MainActor
private final class CodexTestSessionFactory: CodexTerminalSessionCreating {
    private(set) var startDirectories: [URL] = []
    func makeSession(title: String, startDirectory: URL) throws -> CodexTerminalSession {
        startDirectories.append(startDirectory)
        return CodexTerminalSession(title: title, host: CodexTestHost())
    }
}

@MainActor
private final class CodexTestHost: CodexTerminalHosting {
    var onStateChange: ((CodexTerminalSessionState) -> Void)?
    private(set) var terminateCount = 0
    func terminate() { terminateCount += 1 }
}

private extension CodexTerminalSession {
    var terminateCount: Int { (host as? CodexTestHost)?.terminateCount ?? 0 }
}