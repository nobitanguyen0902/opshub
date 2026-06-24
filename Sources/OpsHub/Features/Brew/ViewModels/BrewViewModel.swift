import Combine
import Foundation

@MainActor
final class BrewViewModel: ObservableObject {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case formulae
        case casks
        case outdated

        var id: Self { self }
    }

    @Published private(set) var packages: [BrewPackage] = []
    @Published var searchText = ""
    @Published var selectedFilter: Filter = .all
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var commandLogs: [String] = []
    @Published var isLogExpanded = false

    private let service: any BrewServicing

    init(service: any BrewServicing = BrewService()) {
        self.service = service
    }

    var filteredPackages: [BrewPackage] {
        packages.filter { package in
            matchesSelectedFilter(package) && matchesSearch(package)
        }
    }

    var installedCount: Int { packages.count }
    var outdatedCount: Int { packages.count { $0.status == .outdated } }
    var formulaCount: Int { packages.count { $0.type == .formula } }
    var caskCount: Int { packages.count { $0.type == .cask } }

    func loadPackages() async {
        await perform("brew list") {
            packages = try await service.listInstalledPackages()
        }
    }

    func checkOutdated() async {
        await perform("brew outdated") {
            let outdatedPackages = try await service.listOutdatedPackages()
            let outdatedNames = Set(outdatedPackages.map(\.name))

            if packages.isEmpty {
                packages = try await service.listInstalledPackages()
            }

            packages = packages.map { package in
                BrewPackage(
                    id: package.id,
                    name: package.name,
                    type: package.type,
                    installedVersion: package.installedVersion,
                    latestVersion: package.latestVersion,
                    status: outdatedNames.contains(package.name) ? .outdated : .upToDate,
                    isUpdating: package.isUpdating
                )
            }
        }
    }

    func updatePackage(_ package: BrewPackage) async {
        await perform("brew upgrade \(package.name)") {
            let output = try await service.update(package: package)
            appendLog(output)
            await loadPackages()
        }
    }

    func updateAll() async {
        await perform("brew upgrade") {
            let output = try await service.updateAll()
            appendLog(output)
            await loadPackages()
        }
    }

    func clearLogs() {
        commandLogs.removeAll()
        isLogExpanded = false
    }

    private func perform(_ command: String, operation: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        appendLog("$ \(command)")

        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            errorMessage = error.localizedDescription
            appendLog(error.localizedDescription)
        }
    }

    private func matchesSelectedFilter(_ package: BrewPackage) -> Bool {
        switch selectedFilter {
        case .all:
            true
        case .formulae:
            package.type == .formula
        case .casks:
            package.type == .cask
        case .outdated:
            package.status == .outdated
        }
    }

    private func matchesSearch(_ package: BrewPackage) -> Bool {
        searchText.isEmpty || package.name.localizedCaseInsensitiveContains(searchText)
    }

    private func appendLog(_ message: String) {
        guard !message.isEmpty else { return }
        commandLogs.append(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
