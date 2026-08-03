import Foundation

protocol KanbanWorkspaceValidating: Sendable {
    func validateDraftPath(_ url: URL) async throws -> URL
    func validateStart(_ url: URL) async throws -> URL
}

enum KanbanStartGuardError: LocalizedError, Equatable {
    case missingDirectory
    case notGitRepository
    case notRepositoryRoot
    case dirtyWorkingTree([String])
    case hermesUnavailable
    case missingProfile(String)
    case gatewayStopped
    case workspaceAlreadyActive(UUID)

    var errorDescription: String? {
        switch self {
        case .missingDirectory:
            "The selected workspace directory does not exist."
        case .notGitRepository:
            "The selected workspace is not a Git repository."
        case .notRepositoryRoot:
            "Select the root directory of the Git repository."
        case .dirtyWorkingTree:
            "Commit, stash, or discard workspace changes before starting this workflow."
        case .hermesUnavailable:
            "Hermes CLI is unavailable."
        case let .missingProfile(profile):
            "Hermes profile '\(profile)' is unavailable."
        case .gatewayStopped:
            "Hermes gateway is not running."
        case .workspaceAlreadyActive:
            "This workspace already has an active workflow."
        }
    }
}

struct KanbanWorkspaceValidator: KanbanWorkspaceValidating {
    private let runner: any ShellCommandRunning

    init(runner: any ShellCommandRunning = ShellCommandRunner()) {
        self.runner = runner
    }

    func validateDraftPath(_ url: URL) async throws -> URL {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: canonical.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw KanbanStartGuardError.missingDirectory
        }

        let repositoryRoot: URL
        do {
            let result = try await runner.run(
                "git",
                arguments: ["-C", canonical.path, "rev-parse", "--show-toplevel"]
            )
            guard result.exitCode == 0 else {
                throw KanbanStartGuardError.notGitRepository
            }
            repositoryRoot = URL(
                fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            ).standardizedFileURL.resolvingSymlinksInPath()
        } catch let error as KanbanStartGuardError {
            throw error
        } catch {
            throw KanbanStartGuardError.notGitRepository
        }

        guard repositoryRoot == canonical else {
            throw KanbanStartGuardError.notRepositoryRoot
        }
        return canonical
    }

    func validateStart(_ url: URL) async throws -> URL {
        let canonical = try await validateDraftPath(url)
        let result: ShellCommandResult
        do {
            result = try await runner.run(
                "git",
                arguments: ["-C", canonical.path, "status", "--porcelain"]
            )
        } catch {
            throw KanbanStartGuardError.notGitRepository
        }
        guard result.exitCode == 0 else {
            throw KanbanStartGuardError.notGitRepository
        }

        let dirtyLines = result.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)
        guard dirtyLines.isEmpty else {
            throw KanbanStartGuardError.dirtyWorkingTree(dirtyLines)
        }
        return canonical
    }
}
