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
    func testLoadIfNeededUsesSuccessfulCachedDataUntilManualRefresh() async {
        let service = SequencedDevRoomService(results: [
            [source(id: 1, employeeID: 10, labels: ["Doing"])],
            [source(id: 2, employeeID: 20, labels: ["Test"])]
        ])
        let viewModel = DevRoomViewModel(service: service)

        await viewModel.loadIfNeeded()
        await viewModel.loadIfNeeded()

        let callsAfterCachedLoad = await service.callCount()
        XCTAssertEqual(callsAfterCachedLoad, 1)
        XCTAssertEqual(viewModel.data.issues.map(\.id), [1])

        await viewModel.refresh()

        let callsAfterManualRefresh = await service.callCount()
        XCTAssertEqual(callsAfterManualRefresh, 2)
        XCTAssertEqual(viewModel.data.issues.map(\.id), [2])
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
    func testFailedRefreshAfterEmptySuccessMarksDataStale() async {
        let viewModel = DevRoomViewModel(service: FailAfterFirstDevRoomService(first: []))

        await viewModel.refresh()
        await viewModel.refresh()

        XCTAssertEqual(viewModel.data, .empty)
        guard case .stale = viewModel.loadState else {
            return XCTFail("Expected stale state after successful empty baseline")
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
    func testRefreshClearsSelectedEmployeeWhenTheyAreRemoved() async {
        let service = SequencedDevRoomService(results: [
            [source(id: 1, employeeID: 10, labels: ["Doing"])],
            [source(id: 1, employeeID: 20, labels: ["Doing"])]
        ])
        let viewModel = DevRoomViewModel(service: service)
        await viewModel.refresh()
        viewModel.selectEmployee(10)

        await viewModel.refresh()

        XCTAssertNil(viewModel.selectedEmployeeID)
        XCTAssertNil(viewModel.selectedEmployee)
    }

    @MainActor
    func testConcurrentRefreshRequestsOnlyStartOneLoad() async {
        let service = SlowCountingDevRoomService()
        let viewModel = DevRoomViewModel(service: service)

        let first = Task { await viewModel.refresh() }
        for _ in 0..<100 where viewModel.loadState != .initialLoading {
            await Task.yield()
        }
        let second = Task { await viewModel.refresh() }
        await first.value
        await second.value

        let calls = await service.callCount()
        XCTAssertEqual(calls, 1)
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

    @MainActor
    func testCancellingInFlightRefreshKeepsCachedDataLoaded() async {
        let cachedSource = source(id: 1, employeeID: 10, labels: ["Doing"])
        let service = CancelDuringRequestDevRoomService(first: [cachedSource])
        let viewModel = DevRoomViewModel(service: service)
        await viewModel.refresh()
        let cachedLastUpdated = viewModel.lastUpdated

        let refreshTask = Task { await viewModel.refresh() }
        for _ in 0..<200 {
            if await service.callCount() == 2 { break }
            await Task.yield()
        }

        refreshTask.cancel()
        await refreshTask.value

        XCTAssertEqual(viewModel.loadState, .loaded)
        XCTAssertEqual(viewModel.data.issues.map(\.id), [1])
        XCTAssertEqual(viewModel.lastUpdated, cachedLastUpdated)
        XCTAssertNil(viewModel.animationEvent)
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
    private var calls = 0

    init(results: [[DevRoomSourceIssue]]) {
        self.results = results
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        return results.removeFirst()
    }

    func callCount() -> Int { calls }
}

private actor CountingDevRoomService: DevRoomServicing {
    private var calls = 0

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        return []
    }

    func callCount() -> Int { calls }
}

private actor SlowCountingDevRoomService: DevRoomServicing {
    private var calls = 0

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        try await Task.sleep(for: .milliseconds(30))
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

private actor CancelDuringRequestDevRoomService: DevRoomServicing {
    let first: [DevRoomSourceIssue]
    private var calls = 0

    init(first: [DevRoomSourceIssue]) {
        self.first = first
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        calls += 1
        if calls == 1 { return first }
        try await Task.sleep(for: .seconds(60))
        return []
    }

    func callCount() -> Int { calls }
}
