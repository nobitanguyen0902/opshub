enum BrewPackageStatus: Hashable, Sendable {
    case upToDate
    case outdated
    case updating
    case error
}
