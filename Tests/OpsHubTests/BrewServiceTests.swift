import Foundation
import XCTest
@testable import OpsHub

final class BrewServiceTests: XCTestCase {
    func testListInstalledPackagesMergesOutdatedFormulaAndCaskVersions() async throws {
        let service = BrewService(shellCommandRunner: StubShellCommandRunner())

        let packages = try await service.listInstalledPackages()

        XCTAssertEqual(
            packages.map(PackageSnapshot.init),
            [
                PackageSnapshot(name: "curl", type: .formula, installedVersion: "8.10.0", latestVersion: "8.11.1", status: .outdated),
                PackageSnapshot(name: "git", type: .formula, installedVersion: "-", latestVersion: "-", status: .upToDate),
                PackageSnapshot(name: "firefox", type: .cask, installedVersion: "127.0", latestVersion: "128.0", status: .outdated),
                PackageSnapshot(name: "iterm2", type: .cask, installedVersion: "-", latestVersion: "-", status: .upToDate)
            ]
        )
    }

    func testListOutdatedPackagesParsesFormulaeAndCasksFromJson() async throws {
        let service = BrewService(shellCommandRunner: StubShellCommandRunner())

        let packages = try await service.listOutdatedPackages()

        XCTAssertEqual(
            packages.map(PackageSnapshot.init),
            [
                PackageSnapshot(name: "curl", type: .formula, installedVersion: "8.10.0", latestVersion: "8.11.1", status: .outdated),
                PackageSnapshot(name: "firefox", type: .cask, installedVersion: "127.0", latestVersion: "128.0", status: .outdated)
            ]
        )
    }

    func testUpgradePackageRunsFormulaUpgradeAndReturnsCommandResult() async throws {
        let runner = UpgradeShellCommandRunner()
        let service = BrewService(shellCommandRunner: runner)
        let package = package(name: "ripgrep", type: .formula)

        let result = try await service.upgradePackage(package)

        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [["upgrade", "ripgrep"]])
        XCTAssertEqual(result.stdout, "Upgraded ripgrep")
    }

    func testUpgradePackageRunsCaskUpgradeAndReturnsCommandResult() async throws {
        let runner = UpgradeShellCommandRunner()
        let service = BrewService(shellCommandRunner: runner)
        let package = package(name: "firefox", type: .cask)

        _ = try await service.upgradePackage(package)

        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [["upgrade", "--cask", "firefox"]])
    }

    func testUpgradeAllRunsBrewUpgradeAndReturnsCommandResult() async throws {
        let runner = UpgradeShellCommandRunner()
        let service = BrewService(shellCommandRunner: runner)

        let result = try await service.upgradeAll()

        let arguments = await runner.arguments
        XCTAssertEqual(arguments, [["upgrade"]])
        XCTAssertEqual(result.stdout, "Upgraded ripgrep")
    }

    func testUpgradePackageThrowsWhenCommandResultHasNonZeroExitCode() async {
        let runner = UpgradeShellCommandRunner(exitCode: 1, stderr: "upgrade failed")
        let service = BrewService(shellCommandRunner: runner)

        do {
            _ = try await service.upgradePackage(package(name: "ripgrep", type: .formula))
            XCTFail("Expected upgrade to throw")
        } catch let ShellCommandError.commandFailed(result) {
            XCTAssertEqual(result.exitCode, 1)
            XCTAssertEqual(result.stderr, "upgrade failed")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListOutdatedPackagesThrowsFriendlyErrorForEmptyOutput() async {
        let service = BrewService(shellCommandRunner: OutdatedOutputShellCommandRunner(output: " \n"))

        do {
            _ = try await service.listOutdatedPackages()
            XCTFail("Expected empty output to throw")
        } catch let error as BrewServiceError {
            guard case .emptyOutput = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testListOutdatedPackagesThrowsFriendlyErrorForInvalidJson() async {
        let service = BrewService(shellCommandRunner: OutdatedOutputShellCommandRunner(output: "not json"))

        do {
            _ = try await service.listOutdatedPackages()
            XCTFail("Expected invalid JSON to throw")
        } catch let error as BrewServiceError {
            guard case let .invalidOutdatedPackageData(output) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
            XCTAssertEqual(output, "not json")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShellCommandRunnerTimesOutLongRunningCommand() async {
        let runner = ShellCommandRunner(timeout: 0.01)

        do {
            _ = try await runner.run("/bin/sleep", arguments: ["1"])
            XCTFail("Expected command to time out")
        } catch let ShellCommandError.timedOut(result) {
            XCTAssertNotEqual(result.exitCode, 0)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShellCommandRunnerDrainsLargeStdoutAndStderrBeforeProcessExit() async throws {
        let runner = ShellCommandRunner(timeout: 2)
        let bytesPerStream = 256 * 1024
        let command = """
        (yes O | head -c 262144) &
        (yes E | head -c 262144 >&2) &
        wait
        """

        let result = try await runner.run("/bin/zsh", arguments: ["-c", command])

        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.utf8.count, bytesPerStream)
        XCTAssertEqual(result.stderr.utf8.count, bytesPerStream)
    }

    func testShellCommandRunnerTimeoutTerminatesDescendantsHoldingOutputPipes() async throws {
        let fixture = try LongLivedChildFixture()
        defer { fixture.cleanUp() }
        let runner = ShellCommandRunner(timeout: 2)
        let command = fixture.command
        let task = Task<ShellCommandResult, Error> {
            try await runner.run(command)
        }
        let childPID: pid_t
        do {
            childPID = try await fixture.waitForChildPID()
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        let childExit = expectation(description: "Timeout terminates the original child process")
        let childExitSource = DispatchSource.makeProcessSource(
            identifier: childPID,
            eventMask: .exit,
            queue: .global(qos: .userInitiated)
        )
        childExitSource.setEventHandler { childExit.fulfill() }
        childExitSource.resume()
        defer { childExitSource.cancel() }
        let clock = ContinuousClock()
        let start = clock.now

        do {
            _ = try await task.value
            XCTFail("Expected command to time out")
        } catch let ShellCommandError.timedOut(result) {
            XCTAssertNotEqual(result.exitCode, 0)
            XCTAssertTrue(result.stdout.contains("child-out"))
            XCTAssertTrue(result.stderr.contains("child-err"))
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(3))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await fulfillment(of: [childExit], timeout: 1)
    }

    func testShellCommandRunnerCancellationBeforeLaunchDoesNotSpawnCommand() async throws {
        let markerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opshub-shell-runner-marker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: markerURL) }
        let runner = ShellCommandRunner(timeout: 10)
        let task = Task<ShellCommandResult, Error> {
            while !Task.isCancelled {
                await Task.yield()
            }
            return try await runner.run("/usr/bin/touch", arguments: [markerURL.path])
        }

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testShellCommandRunnerCancellationTerminatesDescendantsHoldingOutputPipes() async throws {
        let fixture = try LongLivedChildFixture()
        defer { fixture.cleanUp() }
        let runner = ShellCommandRunner(timeout: 10)
        let command = fixture.command
        let task = Task<ShellCommandResult, Error> {
            try await runner.run(command)
        }
        let childPID: pid_t
        do {
            childPID = try await fixture.waitForChildPID()
        } catch {
            task.cancel()
            _ = try? await task.value
            throw error
        }
        let childExit = expectation(description: "Cancellation terminates the original child process")
        let childExitSource = DispatchSource.makeProcessSource(
            identifier: childPID,
            eventMask: .exit,
            queue: .global(qos: .userInitiated)
        )
        childExitSource.setEventHandler { childExit.fulfill() }
        childExitSource.resume()
        defer { childExitSource.cancel() }
        let clock = ContinuousClock()
        let start = clock.now

        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            XCTAssertLessThan(start.duration(to: clock.now), .seconds(2))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        await fulfillment(of: [childExit], timeout: 1)
    }

    func testShellCommandRunnerIdentifiesPermissionDeniedOutput() async {
        let runner = ShellCommandRunner()

        do {
            _ = try await runner.run(
                "/bin/zsh",
                arguments: ["-c", "echo permission\\ denied >&2; exit 1"]
            )
            XCTFail("Expected permission denied to throw")
        } catch let ShellCommandError.permissionDenied(result) {
            XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "permission denied")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testFailedCommandOutputIsAppendedToCommandLog() async {
        let viewModel = BrewListViewModel(service: FailingBrewService())

        await viewModel.updateAll()

        XCTAssertEqual(
            viewModel.errorMessage,
            "Homebrew could not complete the command (exit code 1). See Command Log for details."
        )
        XCTAssertTrue(viewModel.commandLogs.joined(separator: "\n").contains("partial output"))
        XCTAssertTrue(viewModel.commandLogs.joined(separator: "\n").contains("command failed"))
    }

    @MainActor
    func testUpdatePackageDoesNotReloadPackageListOrSetGlobalLoadingState() async {
        let package = package(name: "ripgrep", type: .formula)
        let service = UpdatingBrewService(packages: [package])
        let viewModel = BrewListViewModel(service: service)

        await viewModel.loadPackages()
        await viewModel.updatePackage(package)

        let listInstalledCallCount = await service.listInstalledCallCount
        XCTAssertEqual(listInstalledCallCount, 1)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertTrue(viewModel.updatingPackageIDs.isEmpty)
        XCTAssertEqual(viewModel.packages.first?.status, .upToDate)
        XCTAssertEqual(viewModel.packages.first?.installedVersion, "2.0.0")
    }

    @MainActor
    func testMultiplePackageUpdatesAreQueuedWithoutConcurrentBrewCommands() async {
        let ripgrep = package(name: "ripgrep", type: .formula)
        let firefox = package(name: "firefox", type: .cask)
        let service = UpdatingBrewService(packages: [ripgrep, firefox])
        let viewModel = BrewListViewModel(service: service)

        await viewModel.loadPackages()
        async let firstUpdate: Void = viewModel.updatePackage(ripgrep)
        async let secondUpdate: Void = viewModel.updatePackage(firefox)
        _ = await (firstUpdate, secondUpdate)

        let upgradedNames = await service.upgradedNames
        let maxConcurrentUpgrades = await service.maxConcurrentUpgrades
        XCTAssertEqual(upgradedNames, ["ripgrep", "firefox"])
        XCTAssertEqual(maxConcurrentUpgrades, 1)
        XCTAssertEqual(viewModel.outdatedCount, 0)
    }

    private func package(name: String, type: BrewPackageType) -> BrewPackage {
        BrewPackage(
            name: name,
            type: type,
            installedVersion: "1.0.0",
            latestVersion: "2.0.0",
            status: .outdated
        )
    }
}

private final class LongLivedChildFixture {
    private let directoryURL: URL
    private let pidFileURL: URL
    private let scriptFileURL: URL
    private let identity = "opshub-shell-runner-test-\(UUID().uuidString)"

    var command: String {
        let arguments = [scriptFileURL.path, pidFileURL.path, identity]
            .map(Self.shellEscape)
            .joined(separator: " ")
        return "/bin/sh \(arguments) & wait"
    }

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opshub-shell-runner-\(UUID().uuidString)", isDirectory: true)
        pidFileURL = directoryURL.appendingPathComponent("child.pid")
        scriptFileURL = directoryURL.appendingPathComponent("child.sh")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: false)
        let script = """
        echo $$ > "$1"
        trap '' TERM
        count=0
        while [ "$count" -lt 500 ]; do
            printf child-out
            printf child-err >&2
            count=$((count + 1))
            sleep 0.02
        done
        """
        try Data(script.utf8).write(to: scriptFileURL)
    }

    func waitForChildPID() async throws -> pid_t {
        for _ in 0..<200 {
            if let processID = try? childPID() {
                return processID
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LongLivedChildFixtureError.pidWasNotWritten
    }

    func childPID() throws -> pid_t {
        let contents = try String(contentsOf: pidFileURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let processID = pid_t(contents) else {
            throw LongLivedChildFixtureError.invalidPID(contents)
        }
        return processID
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directoryURL)
    }

    private static func shellEscape(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\\"'\\\"'"))'"
    }
}

private enum LongLivedChildFixtureError: Error {
    case pidWasNotWritten
    case invalidPID(String)
}

private struct StubShellCommandRunner: ShellCommandRunning {
    func run(_ command: String) async throws -> ShellCommandResult {
        result(output: "/test/brew\n")
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        switch arguments {
        case ["list", "--formula"]:
            return result(output: "curl\ngit\n")
        case ["list", "--cask"]:
            return result(output: "firefox\niterm2\n")
        case ["outdated", "--json=v2"]:
            return result(output: """
            {
              "formulae": [
                {
                  "name": "curl",
                  "installed_versions": ["8.10.0"],
                  "current_version": "8.11.1"
                }
              ],
              "casks": [
                {
                  "name": "firefox",
                  "installed_versions": ["127.0"],
                  "current_version": "128.0"
                }
              ]
            }
            """)
        default:
            XCTFail("Unexpected command: \(command) \(arguments)")
            return result(output: "")
        }
    }

    private func result(output: String) -> ShellCommandResult {
        ShellCommandResult(stdout: output, stderr: "", exitCode: 0, duration: 0)
    }
}

private struct PackageSnapshot: Equatable {
    let name: String
    let type: BrewPackageType
    let installedVersion: String
    let latestVersion: String
    let status: BrewPackageStatus

    init(_ package: BrewPackage) {
        name = package.name
        type = package.type
        installedVersion = package.installedVersion
        latestVersion = package.latestVersion
        status = package.status
    }

    init(
        name: String,
        type: BrewPackageType,
        installedVersion: String,
        latestVersion: String,
        status: BrewPackageStatus
    ) {
        self.name = name
        self.type = type
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.status = status
    }
}

private actor UpgradeShellCommandRunner: ShellCommandRunning {
    private(set) var arguments: [[String]] = []
    private let exitCode: Int32
    private let stderr: String

    init(exitCode: Int32 = 0, stderr: String = "") {
        self.exitCode = exitCode
        self.stderr = stderr
    }

    func run(_ command: String) async throws -> ShellCommandResult {
        brewPathResult
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        self.arguments.append(arguments)
        return ShellCommandResult(
            stdout: "Upgraded ripgrep",
            stderr: stderr,
            exitCode: exitCode,
            duration: 0
        )
    }

    private var brewPathResult: ShellCommandResult {
        ShellCommandResult(stdout: "/test/brew\n", stderr: "", exitCode: 0, duration: 0)
    }
}

private struct OutdatedOutputShellCommandRunner: ShellCommandRunning {
    let output: String

    func run(_ command: String) async throws -> ShellCommandResult {
        ShellCommandResult(stdout: "/test/brew\n", stderr: "", exitCode: 0, duration: 0)
    }

    func run(_ command: String, arguments: [String]) async throws -> ShellCommandResult {
        ShellCommandResult(stdout: output, stderr: "", exitCode: 0, duration: 0)
    }
}

private struct FailingBrewService: BrewServicing {
    func listInstalledPackages() async throws -> [BrewPackage] { [] }
    func listOutdatedPackages() async throws -> [BrewPackage] { [] }

    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult {
        fatalError("Not used by this test")
    }

    func upgradeAll() async throws -> ShellCommandResult {
        throw ShellCommandError.commandFailed(
            ShellCommandResult(
                stdout: "partial output",
                stderr: "command failed",
                exitCode: 1,
                duration: 0
            )
        )
    }
}

private actor UpdatingBrewService: BrewServicing {
    private let packages: [BrewPackage]
    private var runningUpgrades = 0

    private(set) var listInstalledCallCount = 0
    private(set) var upgradedNames: [String] = []
    private(set) var maxConcurrentUpgrades = 0

    init(packages: [BrewPackage]) {
        self.packages = packages
    }

    func listInstalledPackages() async throws -> [BrewPackage] {
        listInstalledCallCount += 1
        return packages
    }

    func listOutdatedPackages() async throws -> [BrewPackage] {
        packages
    }

    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult {
        runningUpgrades += 1
        maxConcurrentUpgrades = max(maxConcurrentUpgrades, runningUpgrades)
        upgradedNames.append(package.name)
        try? await Task.sleep(nanoseconds: 5_000_000)
        runningUpgrades -= 1

        return ShellCommandResult(
            stdout: "Upgraded \(package.name)",
            stderr: "",
            exitCode: 0,
            duration: 0
        )
    }

    func upgradeAll() async throws -> ShellCommandResult {
        ShellCommandResult(stdout: "Upgraded all", stderr: "", exitCode: 0, duration: 0)
    }
}
