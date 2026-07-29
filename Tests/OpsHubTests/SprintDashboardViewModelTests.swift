import Foundation
import XCTest
@testable import OpsHub

@MainActor
final class SprintDashboardViewModelTests: XCTestCase {
    func testLoadSelectsMilestoneContainingTodayAndBuildsDashboardData() async {
        let alice = member(id: 1, name: "Alice")
        let service = StubSprintDashboardService(
            milestones: [currentMilestone, previousMilestone],
            issuesByMilestone: [
                currentMilestone.title: [
                    issue(id: 1, assignee: alice)
                ]
            ],
            productionBugs: [
                issue(
                    id: 10,
                    labels: ["Bug Production"],
                    assignee: nil,
                    createdAt: "2026-07-30T12:00:00+07:00"
                )
            ]
        )
        let viewModel = makeViewModel(
            service: service,
            selectedUserIDs: [alice.id]
        )

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.selectedMilestoneID, currentMilestone.id)
        XCTAssertEqual(viewModel.data?.ticketCount, 1)
        XCTAssertEqual(viewModel.data?.productionBugCount, 1)
        XCTAssertEqual(viewModel.deliveryState, .loaded)
        XCTAssertEqual(viewModel.bugState, .loaded)
        XCTAssertNotNil(viewModel.lastUpdated)
    }

    func testLoadWithoutCurrentMilestoneKeepsPickerDataAndNoDashboardData() async {
        let service = StubSprintDashboardService(
            milestones: [previousMilestone],
            issuesByMilestone: [:],
            productionBugs: []
        )
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.milestones.map(\.id), [previousMilestone.id])
        XCTAssertNil(viewModel.selectedMilestoneID)
        XCTAssertNil(viewModel.data)
        XCTAssertEqual(viewModel.milestoneState, .loaded)
        XCTAssertEqual(viewModel.deliveryState, .idle)
        XCTAssertEqual(viewModel.bugState, .idle)
    }

    func testSelectingHistoricalMilestoneLoadsItsData() async {
        let service = StubSprintDashboardService(
            milestones: [currentMilestone, previousMilestone],
            issuesByMilestone: [
                currentMilestone.title: [issue(id: 1)],
                previousMilestone.title: [issue(id: 2), issue(id: 3)]
            ],
            productionBugs: []
        )
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()

        await viewModel.selectMilestone(id: previousMilestone.id)

        XCTAssertEqual(viewModel.selectedMilestoneID, previousMilestone.id)
        XCTAssertEqual(viewModel.data?.milestone.id, previousMilestone.id)
        XCTAssertEqual(viewModel.data?.ticketCount, 2)
    }

    func testApplyingSelectedMembersReaggregatesWithoutRefetching() async {
        let alice = member(id: 1, name: "Alice")
        let bob = member(id: 2, name: "Bob")
        let service = StubSprintDashboardService(
            milestones: [currentMilestone],
            issuesByMilestone: [
                currentMilestone.title: [
                    issue(id: 1, assignee: alice),
                    issue(id: 2, assignee: bob)
                ]
            ],
            productionBugs: []
        )
        let viewModel = makeViewModel(
            service: service,
            selectedUserIDs: [alice.id]
        )
        await viewModel.loadIfNeeded()
        let callsBefore = await service.callCounts()

        viewModel.applySelectedUserIDs([bob.id])

        XCTAssertEqual(viewModel.data?.memberSummaries.map(\.member?.id), [bob.id])
        let callsAfter = await service.callCounts()
        XCTAssertEqual(callsAfter.milestones, callsBefore.milestones)
        XCTAssertEqual(callsAfter.issues, callsBefore.issues)
        XCTAssertEqual(callsAfter.bugs, callsBefore.bugs)
    }

    func testBugFailureKeepsLoadedDeliveryAndMarksOnlyBugFailed() async {
        let service = StubSprintDashboardService(
            milestones: [currentMilestone],
            issuesByMilestone: [
                currentMilestone.title: [issue(id: 1)]
            ],
            productionBugs: [],
            bugError: .requestFailed
        )
        let viewModel = makeViewModel(service: service)

        await viewModel.loadIfNeeded()

        XCTAssertEqual(viewModel.data?.ticketCount, 1)
        XCTAssertEqual(viewModel.deliveryState, .loaded)
        guard case .failed = viewModel.bugState else {
            return XCTFail("Expected bug section to fail")
        }
    }

    func testRefreshFailureKeepsPreviousDataAndMarksSectionsStale() async {
        let service = StubSprintDashboardService(
            milestones: [currentMilestone],
            issuesByMilestone: [
                currentMilestone.title: [issue(id: 1)]
            ],
            productionBugs: []
        )
        let viewModel = makeViewModel(service: service)
        await viewModel.loadIfNeeded()
        let previousData = viewModel.data
        await service.setIssueError(.requestFailed)
        await service.setBugError(.requestFailed)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.data, previousData)
        guard case .stale = viewModel.deliveryState else {
            return XCTFail("Expected stale delivery data")
        }
        guard case .stale = viewModel.bugState else {
            return XCTFail("Expected stale bug data")
        }
    }

    func testOlderMilestoneResponseCannotReplaceNewSelection() async {
        let service = StubSprintDashboardService(
            milestones: [currentMilestone, previousMilestone],
            issuesByMilestone: [
                currentMilestone.title: [issue(id: 1)],
                previousMilestone.title: [issue(id: 2), issue(id: 3)]
            ],
            productionBugs: [],
            issueDelays: [
                currentMilestone.title: .milliseconds(150),
                previousMilestone.title: .milliseconds(5)
            ]
        )
        let viewModel = makeViewModel(service: service)

        let initialLoad = Task { await viewModel.loadIfNeeded() }
        try? await Task.sleep(for: .milliseconds(20))
        await viewModel.selectMilestone(id: previousMilestone.id)
        await initialLoad.value

        XCTAssertEqual(viewModel.selectedMilestoneID, previousMilestone.id)
        XCTAssertEqual(viewModel.data?.milestone.id, previousMilestone.id)
        XCTAssertEqual(viewModel.data?.ticketCount, 2)
    }

    func testConcurrentRefreshIsIgnored() async {
        let service = StubSprintDashboardService(
            milestones: [currentMilestone],
            issuesByMilestone: [
                currentMilestone.title: [issue(id: 1)]
            ],
            productionBugs: [],
            issueDelays: [currentMilestone.title: .milliseconds(60)]
        )
        let viewModel = makeViewModel(service: service)

        async let first: Void = viewModel.refresh()
        async let second: Void = viewModel.refresh()
        _ = await (first, second)

        let counts = await service.callCounts()
        XCTAssertEqual(counts.milestones, 1)
        XCTAssertEqual(counts.issues, 1)
        XCTAssertEqual(counts.bugs, 1)
    }

    private func makeViewModel(
        service: StubSprintDashboardService,
        selectedUserIDs: Set<Int> = []
    ) -> SprintDashboardViewModel {
        let currentDate = date("2026-07-30T10:00:00+07:00")
        return SprintDashboardViewModel(
            service: service,
            selectedUserIDs: selectedUserIDs,
            now: { currentDate }
        )
    }

    private var currentMilestone: SprintMilestone {
        milestone(
            id: 31,
            title: "Sprint 2026-W31",
            start: "2026-07-29T00:00:00+07:00",
            due: "2026-08-04T00:00:00+07:00"
        )
    }

    private var previousMilestone: SprintMilestone {
        milestone(
            id: 30,
            title: "Sprint 2026-W30",
            start: "2026-07-22T00:00:00+07:00",
            due: "2026-07-28T00:00:00+07:00"
        )
    }

    private func milestone(
        id: Int,
        title: String,
        start: String,
        due: String
    ) -> SprintMilestone {
        SprintMilestone(
            id: id,
            title: title,
            startDate: date(start),
            dueDate: date(due)
        )
    }

    private func member(id: Int, name: String) -> SprintDashboardMember {
        SprintDashboardMember(
            id: id,
            name: name,
            username: name.lowercased(),
            avatarURL: nil
        )
    }

    private func issue(
        id: Int,
        labels: [String] = [],
        assignee: SprintDashboardMember? = nil,
        createdAt: String? = "2026-07-30T12:00:00+07:00"
    ) -> SprintDashboardIssue {
        SprintDashboardIssue(
            id: id,
            iid: id,
            title: "Issue \(id)",
            project: "social/socom-issues",
            labels: labels,
            assignee: assignee,
            createdAt: createdAt.map(date),
            updatedAt: date("2026-07-30T12:00:00+07:00"),
            webURL: URL(string: "https://gitlab.example.com/issues/\(id)")
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}

private enum StubSprintDashboardError: Error {
    case requestFailed
}

private actor StubSprintDashboardService: SprintDashboardServicing {
    private let milestones: [SprintMilestone]
    private let issuesByMilestone: [String: [SprintDashboardIssue]]
    private let productionBugValues: [SprintDashboardIssue]
    private let issueDelays: [String: Duration]
    private var issueError: StubSprintDashboardError?
    private var bugError: StubSprintDashboardError?
    private var milestoneCallCount = 0
    private var issueCallCount = 0
    private var bugCallCount = 0

    init(
        milestones: [SprintMilestone],
        issuesByMilestone: [String: [SprintDashboardIssue]],
        productionBugs: [SprintDashboardIssue],
        issueError: StubSprintDashboardError? = nil,
        bugError: StubSprintDashboardError? = nil,
        issueDelays: [String: Duration] = [:]
    ) {
        self.milestones = milestones
        self.issuesByMilestone = issuesByMilestone
        productionBugValues = productionBugs
        self.issueError = issueError
        self.bugError = bugError
        self.issueDelays = issueDelays
    }

    func sprintMilestones(projectPath: String) async throws -> [SprintMilestone] {
        milestoneCallCount += 1
        return milestones
    }

    func sprintIssues(
        projectPath: String,
        milestoneTitle: String
    ) async throws -> [SprintDashboardIssue] {
        issueCallCount += 1
        if let delay = issueDelays[milestoneTitle] {
            try await Task.sleep(for: delay)
        }
        if let issueError {
            throw issueError
        }
        return issuesByMilestone[milestoneTitle] ?? []
    }

    func productionBugs(
        projectPath: String,
        createdAfter: Date,
        createdBefore: Date
    ) async throws -> [SprintDashboardIssue] {
        bugCallCount += 1
        if let bugError {
            throw bugError
        }
        return productionBugValues
    }

    func setIssueError(_ error: StubSprintDashboardError?) {
        issueError = error
    }

    func setBugError(_ error: StubSprintDashboardError?) {
        bugError = error
    }

    func callCounts() -> (milestones: Int, issues: Int, bugs: Int) {
        (milestoneCallCount, issueCallCount, bugCallCount)
    }
}
