import Foundation

enum BrewPackageStatus: Hashable, Sendable {
    case upToDate
    case outdated
}

enum BrewPackageKind: Hashable, Sendable {
    case formula
    case cask
}

struct BrewPackage: Identifiable, Hashable, Sendable {
    let name: String
    let installedVersion: String
    let description: String
    let status: BrewPackageStatus
    let kind: BrewPackageKind

    var id: String { name }

    init(
        name: String,
        installedVersion: String,
        description: String,
        status: BrewPackageStatus = .upToDate,
        kind: BrewPackageKind = .formula
    ) {
        self.name = name
        self.installedVersion = installedVersion
        self.description = description
        self.status = status
        self.kind = kind
    }
}
