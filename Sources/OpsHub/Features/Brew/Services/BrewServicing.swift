import Foundation

protocol BrewServicing: Sendable {
    func installedPackages() async throws -> [BrewPackage]
}

struct BrewService: BrewServicing {
    private let shell: any ShellExecuting

    init(shell: any ShellExecuting = ShellExecutor()) {
        self.shell = shell
    }

    func installedPackages() async throws -> [BrewPackage] {
        let output = try await shell.run("/usr/bin/env", arguments: ["brew", "list", "--versions"])
        return output
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let columns = line.split(separator: " ", maxSplits: 1).map(String.init)
                guard let name = columns.first else { return nil }
                return BrewPackage(
                    name: name,
                    version: columns.dropFirst().joined(separator: " "),
                    description: "Installed with Homebrew"
                )
            }
    }
}
