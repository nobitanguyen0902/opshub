import Foundation

protocol BrewServicing: Sendable {
    func listFormulae() async throws -> [BrewPackage]
    func listCasks() async throws -> [BrewPackage]
    func listInstalledPackages() async throws -> [BrewPackage]
    func listOutdatedPackages() async throws -> [BrewPackage]
    func update(package: BrewPackage) async throws -> String
    func updateAll() async throws -> String
}

extension BrewServicing {
    func installedPackages() async throws -> [BrewPackage] {
        try await listInstalledPackages()
    }

    func listOutdatedPackages() async throws -> [BrewPackage] {
        []
    }

    func update(package: BrewPackage) async throws -> String {
        ""
    }

    func updateAll() async throws -> String {
        ""
    }
}
