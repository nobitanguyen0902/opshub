import Foundation

struct BrewPackage: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let type: BrewPackageType
    let installedVersion: String
    let latestVersion: String
    let status: BrewPackageStatus
    var isUpdating: Bool

    init(
        id: UUID = UUID(),
        name: String,
        type: BrewPackageType,
        installedVersion: String,
        latestVersion: String,
        status: BrewPackageStatus = .upToDate,
        isUpdating: Bool = false
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.installedVersion = installedVersion
        self.latestVersion = latestVersion
        self.status = status
        self.isUpdating = isUpdating
    }
}
