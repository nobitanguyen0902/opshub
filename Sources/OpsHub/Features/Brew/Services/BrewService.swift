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

    func upgradePackage(_ package: BrewPackage) async throws -> ShellCommandResult {
        let brewPath = try await resolveBrewPath()
        var arguments = ["upgrade"]
        if package.type == .cask {
            arguments.append("--cask")
        }
        arguments.append(package.name)
        return try await runUpgrade(at: brewPath, arguments: arguments)
    }

    func upgradeAll() async throws -> ShellCommandResult {
        let brewPath = try await resolveBrewPath()
        return try await runUpgrade(at: brewPath, arguments: ["upgrade"])
    }

    private func runUpgrade(at brewPath: String, arguments: [String]) async throws -> ShellCommandResult {
        let result = try await shellCommandRunner.run(brewPath, arguments: arguments)
        guard result.exitCode == 0 else {
            throw ShellCommandError.commandFailed(result)
        }
        return result
    }

    private func listPackages(
        at brewPath: String,
        arguments: [String],
        type: BrewPackageType
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
                    status: .upToDate
                )
            }
    }

    private func getOutdatedPackages(at brewPath: String) async throws -> [BrewPackage] {
        let output = try await shellCommandRunner.run(
            brewPath,
            arguments: ["outdated", "--json=v2"]
        ).stdout
        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw BrewServiceError.emptyOutput
        }

        let response: OutdatedPackagesResponse
        do {
            response = try JSONDecoder().decode(OutdatedPackagesResponse.self, from: Data(output.utf8))
        } catch {
            throw BrewServiceError.invalidOutdatedPackageData(output: output)
        }

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
                    status: .upToDate
                )
            }

            return BrewPackage(
                id: package.id,
                name: package.name,
                type: package.type,
                installedVersion: outdatedPackage.installedVersion,
                latestVersion: outdatedPackage.latestVersion,
                status: .outdated
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
    case emptyOutput
    case invalidOutdatedPackageData(output: String)

    var commandOutput: String? {
        switch self {
        case let .invalidOutdatedPackageData(output):
            output
        case .brewNotInstalled, .emptyOutput:
            nil
        }
    }

    var errorDescription: String? {
        switch self {
        case .brewNotInstalled:
            "Homebrew is not installed. Install Homebrew and try again."
        case .emptyOutput:
            "Homebrew returned no data. Please try again."
        case .invalidOutdatedPackageData:
            "Homebrew returned data the app could not read. Please update Homebrew and try again."
        }
    }
}
