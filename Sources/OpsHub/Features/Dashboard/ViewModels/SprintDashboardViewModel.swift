import Foundation

enum SprintDashboardSectionState: Equatable {
    case idle
    case loading
    case loaded
    case stale(String)
    case failed(String)

    var isLoading: Bool {
        if case .loading = self {
            return true
        }
        return false
    }

    var message: String? {
        switch self {
        case let .stale(message), let .failed(message):
            message
        case .idle, .loading, .loaded:
            nil
        }
    }
}

@MainActor
final class SprintDashboardViewModel: ObservableObject {
    static let autoRefreshInterval: Duration = .seconds(5 * 60)

    @Published private(set) var milestones: [SprintMilestone] = []
    @Published private(set) var selectedMilestoneID: Int?
    @Published private(set) var data: SprintDashboardData?
    @Published private(set) var milestoneState: SprintDashboardSectionState = .idle
    @Published private(set) var deliveryState: SprintDashboardSectionState = .idle
    @Published private(set) var bugState: SprintDashboardSectionState = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var selectedUserIDs: Set<Int>

    private let service: any SprintDashboardServicing
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private var rawSprintIssues: [SprintDashboardIssue] = []
    private var rawProductionBugs: [SprintDashboardIssue] = []
    private var hasSuccessfulDelivery = false
    private var hasSuccessfulBugs = false
    private var hasLoaded = false
    private var isRefreshing = false
    private var loadGeneration = 0

    init(
        service: any SprintDashboardServicing,
        selectedUserIDs: Set<Int> = [],
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = SprintDashboardViewModel.vietnamCalendar()
    ) {
        self.service = service
        self.selectedUserIDs = selectedUserIDs
        self.now = now
        self.calendar = calendar
    }

    var selectedMilestone: SprintMilestone? {
        guard let selectedMilestoneID else { return nil }
        return milestones.first { $0.id == selectedMilestoneID }
    }

    var isLoading: Bool {
        milestoneState.isLoading
            || deliveryState.isLoading
            || bugState.isLoading
    }

    var hasConfiguredMembers: Bool {
        selectedUserIDs.isEmpty == false
    }

    func loadIfNeeded() async {
        guard hasLoaded == false else { return }
        await refresh()
    }

    func refresh() async {
        guard isRefreshing == false else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previousMilestoneState = milestoneState
        milestoneState = .loading

        do {
            let loadedMilestones = try await service.sprintMilestones(
                projectPath: GitLabWorkflowProject.path
            )
            guard Task.isCancelled == false else {
                milestoneState = previousMilestoneState
                return
            }

            milestones = loadedMilestones
            milestoneState = .loaded
            hasLoaded = true

            let nextMilestone = selectedMilestone
                ?? SprintDashboardAggregator.currentMilestone(
                    from: loadedMilestones,
                    now: now(),
                    calendar: calendar
                )
            guard let nextMilestone else {
                selectedMilestoneID = nil
                clearSelectionData()
                return
            }

            if selectedMilestoneID != nextMilestone.id {
                prepareForSelection(nextMilestone.id)
            }
            await loadData(for: nextMilestone, generation: loadGeneration)
        } catch where Task.isCancelled {
            milestoneState = previousMilestoneState
        } catch {
            let message = error.localizedDescription
            milestoneState = milestones.isEmpty ? .failed(message) : .stale(message)
        }
    }

    func selectMilestone(id: Int) async {
        guard let milestone = milestones.first(where: { $0.id == id }) else {
            return
        }
        if selectedMilestoneID != id {
            prepareForSelection(id)
        }
        await loadData(for: milestone, generation: loadGeneration)
    }

    func applySelectedUserIDs(_ ids: Set<Int>) {
        selectedUserIDs = ids
        rebuildData()
    }

    func retryDelivery() async {
        guard let selectedMilestone else { return }
        await loadData(for: selectedMilestone, generation: loadGeneration)
    }

    func retryBugs() async {
        guard let selectedMilestone else { return }
        await loadData(for: selectedMilestone, generation: loadGeneration)
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

    private func prepareForSelection(_ id: Int) {
        loadGeneration += 1
        selectedMilestoneID = id
        rawSprintIssues = []
        rawProductionBugs = []
        hasSuccessfulDelivery = false
        hasSuccessfulBugs = false
        data = nil
        deliveryState = .idle
        bugState = .idle
    }

    private func clearSelectionData() {
        loadGeneration += 1
        rawSprintIssues = []
        rawProductionBugs = []
        hasSuccessfulDelivery = false
        hasSuccessfulBugs = false
        data = nil
        deliveryState = .idle
        bugState = .idle
    }

    private func loadData(
        for milestone: SprintMilestone,
        generation: Int
    ) async {
        let previousDeliveryState = deliveryState
        let previousBugState = bugState
        deliveryState = .loading
        bugState = .loading

        let boundary = SprintDashboardAggregator.sprintBoundary(
            for: milestone,
            calendar: calendar
        )
        async let deliveryResult = Self.capture {
            try await self.service.sprintIssues(
                projectPath: GitLabWorkflowProject.path,
                milestoneTitle: milestone.title
            )
        }
        async let bugResult = Self.capture {
            try await self.service.productionBugs(
                projectPath: GitLabWorkflowProject.path,
                createdAfter: boundary.start,
                createdBefore: boundary.endExclusive
            )
        }
        let (loadedDelivery, loadedBugs) = await (deliveryResult, bugResult)

        guard generation == loadGeneration,
              selectedMilestoneID == milestone.id
        else {
            return
        }

        var loadedAnySection = false
        switch loadedDelivery {
        case let .success(issues):
            rawSprintIssues = issues
            hasSuccessfulDelivery = true
            deliveryState = .loaded
            loadedAnySection = true
        case let .failure(message):
            deliveryState = hasSuccessfulDelivery
                ? .stale(message)
                : .failed(message)
        case .cancelled:
            deliveryState = previousDeliveryState
        }

        switch loadedBugs {
        case let .success(issues):
            rawProductionBugs = issues
            hasSuccessfulBugs = true
            bugState = .loaded
            loadedAnySection = true
        case let .failure(message):
            bugState = hasSuccessfulBugs
                ? .stale(message)
                : .failed(message)
        case .cancelled:
            bugState = previousBugState
        }

        rebuildData()
        if loadedAnySection {
            lastUpdated = now()
        }
    }

    private func rebuildData() {
        guard let selectedMilestone else {
            data = nil
            return
        }
        data = SprintDashboardAggregator.makeData(
            milestone: selectedMilestone,
            sprintIssues: rawSprintIssues,
            productionBugs: rawProductionBugs,
            selectedUserIDs: selectedUserIDs,
            calendar: calendar
        )
    }

    private static func capture<Value: Sendable>(
        operation: @escaping @Sendable () async throws -> Value
    ) async -> SprintDashboardRequestResult<Value> {
        do {
            return .success(try await operation())
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private static func vietnamCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }
}

private enum SprintDashboardRequestResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(String)
    case cancelled
}
