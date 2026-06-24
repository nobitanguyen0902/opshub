import Foundation

protocol BrewServicing: Sendable {
    func listFormulae() async throws -> [BrewPackage]
    func listCasks() async throws -> [BrewPackage]
    func listInstalledPackages() async throws -> [BrewPackage]
}

extension BrewServicing {
    func installedPackages() async throws -> [BrewPackage] {
        try await listInstalledPackages()
    }
}
