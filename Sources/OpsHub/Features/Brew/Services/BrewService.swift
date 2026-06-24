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
        return try await formulae + casks
    }

    func listOutdatedPackages() async throws -> [BrewPackage] {
        let brewPath = try await resolveBrewPath()
        async let formulae = listPackages(
            at: brewPath,
            arguments: ["outdated", "--formula", "--quiet"],
            type: .formula,
            status: .outdated
        )
        async let casks = listPackages(
            at: brewPath,
            arguments: ["outdated", "--cask", "--quiet"],
            type: .cask,
            status: .outdated
        )
        return try await formulae + casks
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
