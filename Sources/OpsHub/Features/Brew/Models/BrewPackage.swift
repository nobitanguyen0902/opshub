import Foundation

enum BrewPackageStatus: Hashable, Sendable {
    case upToDate
}

struct BrewPackage: Identifiable, Hashable, Sendable {
    let name: String
    let installedVersion: String
    let description: String
    let status: BrewPackageStatus

    var id: String { name }

    init(
        name: String,
        installedVersion: String,
        description: String,
        status: BrewPackageStatus = .upToDate
    ) {
        self.name = name
        self.installedVersion = installedVersion
        self.description = description
        self.status = status
    }
}
