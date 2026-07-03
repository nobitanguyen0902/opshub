import Combine
import Foundation

@MainActor
final class BrewListViewModel: ObservableObject {
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
    @Published private(set) var isUpdatingAll = false
    @Published private(set) var updatingPackageIDs = Set<BrewPackage.ID>()
    @Published private(set) var errorMessage: String?
    @Published private(set) var commandLogs: [String] = []
    @Published var isLogExpanded = false

    private let service: any BrewServicing
    private let updateQueue = SerialTaskQueue()

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

            if packages.isEmpty {
                packages = try await service.listInstalledPackages()
            }

            packages = packages.map { package in
                let outdatedPackage = outdatedPackages.first {
                    $0.name == package.name && $0.type == package.type
                }

                return BrewPackage(
                    id: package.id,
                    name: package.name,
                    type: package.type,
                    installedVersion: outdatedPackage?.installedVersion ?? package.installedVersion,
                    latestVersion: outdatedPackage?.latestVersion ?? package.latestVersion,
                    status: outdatedPackage == nil ? .upToDate : .outdated
                )
            }
        }
    }

    func updatePackage(_ package: BrewPackage) async {
        guard !updatingPackageIDs.contains(package.id), !isUpdatingAll else { return }

        updatingPackageIDs.insert(package.id)
        errorMessage = nil
        appendLog("$ brew upgrade \(package.name)")

        defer { updatingPackageIDs.remove(package.id) }

        do {
            let result = try await updateQueue.run {
                try await self.service.upgradePackage(package)
            }
            appendLog(result.stdout)
            appendLog(result.stderr)
            markPackageUpdated(package)
        } catch {
            errorMessage = error.localizedDescription
            appendFailedCommandOutput(from: error)
            appendLog("Error: \(error.localizedDescription)")
        }
    }

    func updateAll() async {
        guard !isUpdatingAll else { return }

        isUpdatingAll = true
        errorMessage = nil
        appendLog("$ brew upgrade")

        defer { isUpdatingAll = false }

        do {
            let result = try await updateQueue.run {
                try await self.service.upgradeAll()
            }
            appendLog(result.stdout)
            appendLog(result.stderr)
            markAllPackagesUpdated()
        } catch {
            errorMessage = error.localizedDescription
            appendFailedCommandOutput(from: error)
            appendLog("Error: \(error.localizedDescription)")
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
            appendFailedCommandOutput(from: error)
            appendLog("Error: \(error.localizedDescription)")
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
        let timestamp = Self.logTimestampFormatter.string(from: .now)
        let entry = message.trimmingCharacters(in: .whitespacesAndNewlines)
        commandLogs.append("[\(timestamp)] \(entry)")
    }

    private func appendFailedCommandOutput(from error: Error) {
        if let shellError = error as? ShellCommandError, let result = shellError.result {
            appendLog(result.stdout)
            appendLog(result.stderr)
        }

        if let brewError = error as? BrewServiceError, let output = brewError.commandOutput {
            appendLog(output)
        }
    }

    private func markPackageUpdated(_ package: BrewPackage) {
        packages = packages.map { currentPackage in
            guard currentPackage.id == package.id else { return currentPackage }
            return updatedPackage(from: currentPackage)
        }
    }

    private func markAllPackagesUpdated() {
        packages = packages.map(updatedPackage)
    }

    private func updatedPackage(from package: BrewPackage) -> BrewPackage {
        BrewPackage(
            id: package.id,
            name: package.name,
            type: package.type,
            installedVersion: package.latestVersion,
            latestVersion: package.latestVersion,
            status: .upToDate
        )
    }

    private static let logTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private actor SerialTaskQueue {
    private var previousTask: Task<Void, Never>?

    func run<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let previousTask = previousTask
        let operationTask = Task<T, Error> {
            await previousTask?.value
            return try await operation()
        }
        self.previousTask = Task {
            _ = try? await operationTask.value
        }
        return try await operationTask.value
    }
}
