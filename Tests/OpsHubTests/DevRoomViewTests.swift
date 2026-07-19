import XCTest
@testable import OpsHub

final class DevRoomViewTests: XCTestCase {
    @MainActor
    func testWorkflowSummaryDataExcludesHiddenAssignees() async {
        let service = DevRoomViewStubService(issues: [
            source(id: 1, employeeID: 10, labels: ["Todo"]),
            source(id: 2, employeeID: 20, labels: ["Passed"])
        ])
        let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [20])

        await viewModel.refresh()

        let view = DevRoomView(viewModel: viewModel)
        XCTAssertEqual(view.workflowSummaryData.count(for: .todo), 0)
        XCTAssertEqual(view.workflowSummaryData.count(for: .passed), 1)
    }
}

private actor DevRoomViewStubService: DevRoomServicing {
    private let issues: [DevRoomSourceIssue]

    init(issues: [DevRoomSourceIssue]) {
        self.issues = issues
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        issues
    }
}

private func source(id: Int, employeeID: Int, labels: [String]) -> DevRoomSourceIssue {
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
