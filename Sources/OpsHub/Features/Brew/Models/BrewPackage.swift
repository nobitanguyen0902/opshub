import Foundation

struct BrewPackage: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let type: BrewPackageType
    let installedVersion: String
    let latestVersion: String
    let status: BrewPackageStatus

    init(
        id: UUID = UUID(),
        name: String,
        type: BrewPackageType,
        installedVersion: String,
        latestVersion: String,
        status: BrewPackageStatus = .upToDate
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.status = status
    }
}
