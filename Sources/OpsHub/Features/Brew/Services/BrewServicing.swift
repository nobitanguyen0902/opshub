import Foundation

protocol BrewServicing: Sendable {
    func listInstalledPackages() async throws -> [BrewPackage]
    func listOutdatedPackages() async throws -> [BrewPackage]
    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult
    func upgradeAll() async throws -> ShellCommandResult
}
