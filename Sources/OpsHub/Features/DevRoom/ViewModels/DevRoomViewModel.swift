import Foundation

enum DevRoomLoadState: Equatable {
    case idle
    case initialLoading
    case loaded
    case refreshing
    case stale(String)
    case failed(String)
}

struct DevRoomAnimationEvent: Equatable {
    let generation: Int
    let employeeIDs: Set<Int>
}

@MainActor
final class DevRoomViewModel: ObservableObject {
    static let autoRefreshInterval: Duration = .seconds(2 * 60)

    @Published private(set) var data: DevRoomData = .empty
    @Published private(set) var loadState: DevRoomLoadState = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var animationEvent: DevRoomAnimationEvent?
    @Published private(set) var selectedUserIDs: Set<Int>
    @Published var selectedStage: DevRoomWorkflowStage?
    @Published var selectedEmployeeID: Int?

    private let service: any DevRoomServicing
    private var snapshot: DevRoomSnapshot?
    private var isLoading = false
    private var animationGeneration = 0
    private var hasLoaded = false

    init(service: any DevRoomServicing, selectedUserIDs: Set<Int> = []) {
        self.service = service
        self.selectedUserIDs = selectedUserIDs
    }

    var visibleData: DevRoomData { data.filtered(userIDs: selectedUserIDs) }
    var hasConfiguredMembers: Bool { selectedUserIDs.isEmpty == false }

    var displayedEmployees: [DevRoomEmployeeSummary] {
        guard let selectedStage else { return visibleData.employees }
        return visibleData.employees.filter { $0.count(for: selectedStage) > 0 }
    }

    var selectedEmployee: DevRoomEmployeeSummary? {
        guard let selectedEmployeeID else { return nil }
        return visibleData.employees.first { $0.id == selectedEmployeeID }
    }

    func toggleStage(_ stage: DevRoomWorkflowStage) {
        selectedStage = selectedStage == stage ? nil : stage
    }

    func selectEmployee(_ id: Int?) {
        selectedEmployeeID = id
    }

    func applySelectedUserIDs(_ ids: Set<Int>) {
        selectedUserIDs = ids
        clearSelectionIfHidden()
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await refresh()
    }

    func retry() async {
        await refresh()
    }

    func autoRefresh(every interval: Duration = autoRefreshInterval) async {
        while Task.isCancelled == false {
            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }

            guard Task.isCancelled == false else { return }
            await refresh()
        }
    }

    func refresh() async {
        guard isLoading == false else { return }

        let previousLoadState = loadState
        isLoading = true
        loadState = hasLoaded ? .refreshing : .initialLoading
        defer { isLoading = false }

        do {
            let sources = try await service.openIssues(projectPath: GitLabWorkflowProject.path)
            let newData = DevRoomAggregator.makeData(from: sources)
            let newSnapshot = DevRoomSnapshot(data: newData)

            if let snapshot {
                let changes = DevRoomSnapshotDiffer.diff(from: snapshot, to: newSnapshot)
                if changes.hasChanges {
                    animationGeneration += 1
                    animationEvent = DevRoomAnimationEvent(
                        generation: animationGeneration,
                        employeeIDs: changes.employeeIDs
                    )
                }
            }

            snapshot = newSnapshot
            data = newData
            lastUpdated = .now
            hasLoaded = true
            loadState = .loaded

            clearSelectionIfHidden()
        } catch where Task.isCancelled {
            loadState = previousLoadState
        } catch {
            let message = error.localizedDescription
            loadState = hasLoaded ? .stale(message) : .failed(message)
        }
    }

    private func clearSelectionIfHidden() {
        guard let selectedEmployeeID else { return }
        if displayedEmployees.contains(where: { $0.id == selectedEmployeeID }) == false {
            self.selectedEmployeeID = nil
        }
    }
}
