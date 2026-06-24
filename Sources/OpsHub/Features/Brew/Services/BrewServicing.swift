import Foundation

protocol BrewServicing: Sendable {
    func listFormulae() async throws -> [BrewPackage]
    func listCasks() async throws -> [BrewPackage]
    func listInstalledPackages() async throws -> [BrewPackage]
    func listOutdatedPackages() async throws -> [BrewPackage]
    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult
    func upgradeAll() async throws -> ShellCommandResult
}

extension BrewServicing {
    func installedPackages() async throws -> [BrewPackage] {
        try await listInstalledPackages()
    }

    func listOutdatedPackages() async throws -> [BrewPackage] {
        []
    }

    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult {
        ShellCommandResult(stdout: "", stderr: "", exitCode: 0, duration: 0)
    }

    func upgradeAll() async throws -> ShellCommandResult {
        ShellCommandResult(stdout: "", stderr: "", exitCode: 0, duration: 0)
    }
}
