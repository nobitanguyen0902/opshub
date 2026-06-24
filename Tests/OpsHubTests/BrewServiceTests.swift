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
