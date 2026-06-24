import Foundation

struct BrewService: BrewServicing {
    private static let preferredBrewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    private let shellCommandRunner: any ShellCommandRunning

    init(shellCommandRunner: any ShellCommandRunning = ShellCommandRunner()) {
        self.shellCommandRunner = shellCommandRunner
    }

    func listFormulae() async throws -> [BrewPackage] {
        let brewPath = try await resolveBrewPath()
        return try await listPackages(
            at: brewPath,
            arguments: ["list", "--formula"],
            type: .formula
        )
    }

    func listCasks() async throws -> [BrewPackage] {
        let brewPath = try await resolveBrewPath()
        return try await listPackages(
            at: brewPath,
            arguments: ["list", "--cask"],
            type: .cask
        )
    }

    func listInstalledPackages() async throws -> [BrewPackage] {
        let brewPath = try await resolveBrewPath()
        async let formulae = listPackages(
            at: brewPath,
            arguments: ["list", "--formula"],
            type: .formula
        )
        async let casks = listPackages(
            at: brewPath,
            arguments: ["list", "--cask"],
            type: .cask
        )
        async let outdatedPackages = getOutdatedPackages(at: brewPath)

        return mergeOutdatedPackages(
            try await formulae + casks,
            outdatedPackages: try await outdatedPackages
        )
    }

    func listOutdatedPackages() async throws -> [BrewPackage] {
        let brewPath = try await resolveBrewPath()
        return try await getOutdatedPackages(at: brewPath)
    }

    func update(package: BrewPackage) async throws -> String {
        let brewPath = try await resolveBrewPath()
        var arguments = ["upgrade"]
        if package.type == .cask {
            arguments.append("--cask")
        }
        arguments.append(package.name)
        return try await shellCommandRunner.run(brewPath, arguments: arguments).stdout
    }

    func updateAll() async throws -> String {
        let brewPath = try await resolveBrewPath()
        return try await shellCommandRunner.run(brewPath, arguments: ["upgrade"]).stdout
    }

    private func listPackages(
        at brewPath: String,
        arguments: [String],
        type: BrewPackageType,
        status: BrewPackageStatus = .upToDate
    ) async throws -> [BrewPackage] {
        let output = try await shellCommandRunner.run(brewPath, arguments: arguments).stdout

        return output
            .split(whereSeparator: \.isNewline)
            .map { name in
                BrewPackage(
                    name: String(name),
                    type: type,
                    installedVersion: "-",
                    latestVersion: "-",
                    status: status
                )
            }
    }

    private func getOutdatedPackages(at brewPath: String) async throws -> [BrewPackage] {
        let output = try await shellCommandRunner.run(
            brewPath,
            arguments: ["outdated", "--json=v2"]
        ).stdout
        let response = try JSONDecoder().decode(OutdatedPackagesResponse.self, from: Data(output.utf8))

        return response.formulae.map { package in
            BrewPackage(
                name: package.name,
                type: .formula,
                installedVersion: package.installedVersions.first ?? "-",
                latestVersion: package.currentVersion ?? "-",
                status: .outdated
            )
        } + response.casks.map { package in
            BrewPackage(
                name: package.name,
                type: .cask,
                installedVersion: package.installedVersions.first ?? "-",
                latestVersion: package.currentVersion ?? "-",
                status: .outdated
            )
        }
    }

    private func mergeOutdatedPackages(
        _ installedPackages: [BrewPackage],
        outdatedPackages: [BrewPackage]
    ) -> [BrewPackage] {
        let outdatedPackagesByKey = Dictionary(
            outdatedPackages.map { (PackageKey(name: $0.name, type: $0.type), $0) },
            uniquingKeysWith: { latest, _ in latest }
        )

        return installedPackages.map { package in
            guard let outdatedPackage = outdatedPackagesByKey[PackageKey(name: package.name, type: package.type)] else {
                return BrewPackage(
                    id: package.id,
                    name: package.name,
                    type: package.type,
                    installedVersion: package.installedVersion,
                    latestVersion: package.installedVersion == "-" ? "-" : package.installedVersion,
                    status: .upToDate,
                    isUpdating: package.isUpdating
                )
            }

            return BrewPackage(
                id: package.id,
                name: package.name,
                type: package.type,
                installedVersion: outdatedPackage.installedVersion,
                latestVersion: outdatedPackage.latestVersion,
                status: .outdated,
                isUpdating: package.isUpdating
            )
        }
    }

    private func resolveBrewPath() async throws -> String {
        if let brewPath = Self.preferredBrewPaths.first(where: FileManager.default.isExecutableFile) {
            return brewPath
        }

        do {
            let output = try await shellCommandRunner.run("/usr/bin/which", arguments: ["brew"]).stdout
            if let brewPath = output
                .split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                return brewPath
            }
        } catch {
            // A non-zero exit status from `which brew` means Homebrew is absent.
        }

        throw BrewServiceError.brewNotInstalled
    }

    private struct OutdatedPackagesResponse: Decodable {
        let formulae: [OutdatedPackage]
        let casks: [OutdatedPackage]
    }

    private struct OutdatedPackage: Decodable {
        let name: String
        let installedVersions: [String]
        let currentVersion: String?

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }
    }

    private struct PackageKey: Hashable {
        let name: String
        let type: BrewPackageType
    }
}

enum BrewServiceError: LocalizedError {
    case brewNotInstalled

    var errorDescription: String? {
        switch self {
        case .brewNotInstalled:
            "Homebrew is not installed. Install Homebrew and try again."
        }
    }
}
