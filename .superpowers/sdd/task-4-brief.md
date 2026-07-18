### Task 4: DevRoomViewModel load, cache, filter và auto-refresh

**Files:**
- Create: Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift
- Create: Tests/OpsHubTests/DevRoomViewModelTests.swift

**Interfaces:**
- Consumes:
  - DevRoomServicing.openIssues(projectPath:)
  - DevRoomAggregator.makeData(from:)
  - DevRoomSnapshotDiffer.diff(from:to:)
- Produces:
  - DevRoomLoadState
  - DevRoomAnimationEvent
  - DevRoomViewModel.loadIfNeeded(), refresh(), retry(), autoRefresh(every:)
  - displayedEmployees, selectedStage, selectedEmployee

- [ ] **Step 1: Viết failing ViewModel tests**

Tạo Tests/OpsHubTests/DevRoomViewModelTests.swift:

~~~swift
import XCTest
@testable import OpsHub

final class DevRoomViewModelTests: XCTestCase {
    @MainActor
    func testFirstLoadBuildsRoomWithoutAnimationEvent() async {
        let service = SequencedDevRoomService(results: [[source(id: 1, employeeID: 10, labels: ["Doing"])]])
        let viewModel = DevRoomViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.data.total, 1)
        XCTAssertNil(viewModel.animationEvent)
        XCTAssertNotNil(viewModel.lastUpdated)
        XCTAssertEqual(viewModel.loadState, .loaded)
    }

    @MainActor
    func testSecondRefreshPublishesOnlyChangedEmployees() async {
        let service = SequencedDevRoomService(results: [
            [source(id: 1, employeeID: 10, labels: ["Doing"])],
            [source(id: 1, employeeID: 20, labels: ["ToTest"])]
        ])
        let viewModel = DevRoomViewModel(service: service)

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.animationEvent?.employeeIDs, [10, 20])
        XCTAssertEqual(viewModel.animationEvent?.generation, 1)
    }

    @MainActor
    func testFailedRefreshKeepsCachedDataAndSnapshot() async {
        let service = FailAfterFirstDevRoomService(
            first: [source(id: 1, employeeID: 10, labels: ["Doing"])]
        )
        let viewModel = DevRoomViewModel(service: service)

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.data.total, 1)
        XCTAssertNil(viewModel.animationEvent)
        guard case .stale = viewModel.loadState else {
            return XCTFail("Expected stale state")
        }
    }

    @MainActor
    func testStageFilterKeepsOnlyMatchingEmployees() async {
        let service = SequencedDevRoomService(results: [[
            source(id: 1, employeeID: 10, labels: ["Doing"]),
            source(id: 2, employeeID: 20, labels: ["Test"])
        ]])
        let viewModel = DevRoomViewModel(service: service)
        await viewModel.refresh()

        viewModel.toggleStage(.test)

        XCTAssertEqual(viewModel.displayedEmployees.map(\.employee.id), [20])
        XCTAssertEqual(viewModel.data.employees.first(where: { $0.id == 20 })?.total, 1)
    }

    @MainActor
    func testAutoRefreshRunsAndStopsWhenCancelled() async {
        let service = CountingDevRoomService()
        let viewModel = DevRoomViewModel(service: service)
        let task = Task { await viewModel.autoRefresh(every: .milliseconds(80)) }

        for _ in 0..<200 {
            if await service.callCount() > 0 { break }
            try? await Task.sleep(for: .milliseconds(1))
        }
        let callsAfterInterval = await service.callCount()
        XCTAssertGreaterThan(callsAfterInterval, 0)

        task.cancel()
        await task.value
        let callsAtCancel = await service.callCount()
        try? await Task.sleep(for: .milliseconds(100))
        let callsAfterCancel = await service.callCount()
        XCTAssertEqual(callsAfterCancel, callsAtCancel)
    }
}

private func source(
    id: Int,
    employeeID: Int,
    labels: [String]
) -> DevRoomSourceIssue {
    DevRoomSourceIssue(
        id: id,
        iid: id,
        title: "Issue \(id)",
        labels: labels,
        assignee: DevRoomEmployee(id: employeeID, name: "User \(employeeID)", username: nil, avatarURL: nil),
        updatedAt: nil,
        webURL: nil
    )
}

private actor SequencedDevRoomService: DevRoomServicing {
    var results: [[DevRoomSourceIssue]]

    init(results: [[DevRoomSourceIssue]]) {
        self.results = results
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        results.removeFirst()
    }
}

private actor CountingDevRoomService: DevRoomServicing {
    private var calls = 0
    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        return []
    }
    func callCount() -> Int { calls }
}

private actor FailAfterFirstDevRoomService: DevRoomServicing {
    let first: [DevRoomSourceIssue]
    var calls = 0

    init(first: [DevRoomSourceIssue]) {
        self.first = first
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        if calls == 1 { return first }
        throw GitLabServiceError.requestFailed(503)
    }
}
~~~

- [ ] **Step 2: Chạy tests và xác nhận fail**

Run:

~~~bash
swift test --filter DevRoomViewModelTests
~~~

Expected: build FAIL vì DevRoomViewModel chưa tồn tại.

- [ ] **Step 3: Implement ViewModel**

Tạo Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift:

~~~swift
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
    @Published var selectedStage: DevRoomWorkflowStage?
    @Published var selectedEmployeeID: Int?

    private let service: any DevRoomServicing
    private var snapshot: DevRoomSnapshot?
    private var isLoading = false
    private var animationGeneration = 0
    private var hasLoaded = false

    init(service: any DevRoomServicing) {
        self.service = service
    }

    var displayedEmployees: [DevRoomEmployeeSummary] {
        guard let selectedStage else { return data.employees }
        return data.employees.filter { $0.count(for: selectedStage) > 0 }
    }

    var selectedEmployee: DevRoomEmployeeSummary? {
        guard let selectedEmployeeID else { return nil }
        return data.employees.first { $0.id == selectedEmployeeID }
    }

    func toggleStage(_ stage: DevRoomWorkflowStage) {
        selectedStage = selectedStage == stage ? nil : stage
    }

    func selectEmployee(_ id: Int?) {
        selectedEmployeeID = id
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
            if let selectedEmployeeID,
               data.employees.contains(where: { $0.id == selectedEmployeeID }) == false {
                self.selectedEmployeeID = nil
            }
        } catch {
            let message = error.localizedDescription
            loadState = hasLoaded ? .stale(message) : .failed(message)
        }
    }
}
~~~

- [ ] **Step 4: Chạy targeted tests**

Run:

~~~bash
swift test --filter DevRoomViewModelTests
~~~

Expected: PASS. Nếu XCTest báo await trong autoclosure, đọc callCount vào local variable trước XCTAssert như GitLabDashboardViewModelTests hiện có.

- [ ] **Step 5: Commit ViewModel**

~~~bash
git add Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift Tests/OpsHubTests/DevRoomViewModelTests.swift
git commit -m "feat(dev-room): add refresh and snapshot state"
~~~

---

