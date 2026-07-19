import Foundation
import XCTest
@testable import OpsHub

final class DevRoomAggregationTests: XCTestCase {
    func testStageMatchingNormalizesCaseAndWhitespace() {
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" TODO "]), .todo)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["doing"]), .doing)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["toTEST"]), .toTest)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" testing "]), .testing)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["PASSED"]), .passed)
    }

    func testLegacyTestLabelIsNotAWorkflowStage() {
        XCTAssertNil(DevRoomWorkflowStage.stage(for: ["Test"]))
    }

    func testMultipleWorkflowLabelsUseFurthestStage() {
        XCTAssertEqual(
            DevRoomWorkflowStage.stage(for: ["Doing", "Todo", "Testing"]),
            .testing
        )
    }

    func testAggregationExcludesUnassignedAndNonWorkflowIssues() {
        let alice = employee(id: 1, name: "Alice")
        let sources = [
            source(id: 1, labels: ["Doing"], assignee: alice),
            source(id: 2, labels: ["Backend"], assignee: alice),
            source(id: 3, labels: ["Testing"], assignee: nil)
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.employees.map(\.employee.id), [1])
        XCTAssertEqual(data.employees.first?.total, 1)
        XCTAssertEqual(data.count(for: .doing), 1)
        XCTAssertEqual(data.total, 1)
    }

    func testAggregationGroupsOneEmployeeOnceAndCountsEveryStage() {
        let alice = employee(id: 1, name: "Alice")
        let bob = employee(id: 2, name: "Bob")
        let sources = [
            source(id: 1, labels: ["Todo"], assignee: alice),
            source(id: 2, labels: ["Doing"], assignee: alice),
            source(id: 3, labels: ["Doing"], assignee: bob)
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.employees.map(\.employee.name), ["Alice", "Bob"])
        XCTAssertEqual(data.employees[0].count(for: .todo), 1)
        XCTAssertEqual(data.employees[0].count(for: .doing), 1)
        XCTAssertEqual(data.employees[0].total, 2)
        XCTAssertEqual(data.count(for: .todo), 1)
        XCTAssertEqual(data.count(for: .doing), 2)
        XCTAssertEqual(data.total, 3)
    }

    func testRepresentativeStageUsesFurthestWorkflowStageInsteadOfLargestCount() {
        let alice = employee(id: 1, name: "Alice")
        let sources = [
            source(id: 1, labels: ["Todo"], assignee: alice),
            source(id: 2, labels: ["Todo"], assignee: alice),
            source(id: 3, labels: ["Todo"], assignee: alice),
            source(id: 4, labels: ["Testing"], assignee: alice)
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.employees.first?.representativeStage, .testing)
    }

    func testAggregationCountsDuplicateIssueIDOnceUsingMostRecentlyUpdatedSource() {
        let alice = employee(id: 1, name: "Alice")
        let bob = employee(id: 2, name: "Bob")
        let sources = [
            source(
                id: 1,
                title: "Older",
                labels: ["Doing"],
                assignee: alice,
                updatedAt: Date(timeIntervalSince1970: 1)
            ),
            source(
                id: 1,
                title: "Current",
                labels: ["Testing"],
                assignee: bob,
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.total, 1)
        XCTAssertEqual(data.issues.map(\.title), ["Current"])
        XCTAssertEqual(data.employees.map(\.employee.id), [2])
        XCTAssertEqual(data.count(for: .testing), 1)
        XCTAssertEqual(data.count(for: .doing), 0)
    }

    func testAggregationKeepsFirstDuplicateWhenUpdatedTimestampsMatch() {
        let alice = employee(id: 1, name: "Alice")
        let bob = employee(id: 2, name: "Bob")
        let timestamp = Date(timeIntervalSince1970: 1)
        let sources = [
            source(
                id: 1,
                title: "First in response",
                labels: ["Doing"],
                assignee: alice,
                updatedAt: timestamp
            ),
            source(
                id: 1,
                title: "Later duplicate",
                labels: ["Testing"],
                assignee: bob,
                updatedAt: timestamp
            )
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.issues.map(\.title), ["First in response"])
        XCTAssertEqual(data.employees.map(\.employee.id), [1])
    }

    private func employee(id: Int, name: String) -> DevRoomEmployee {
        DevRoomEmployee(id: id, name: name, username: name.lowercased(), avatarURL: nil)
    }

    private func source(
        id: Int,
        title: String = "Issue",
        labels: [String],
        assignee: DevRoomEmployee?,
        updatedAt: Date? = nil
    ) -> DevRoomSourceIssue {
        DevRoomSourceIssue(
            id: id,
            iid: id,
            title: title,
            labels: labels,
            assignee: assignee,
            updatedAt: updatedAt,
            webURL: URL(string: "https://gitlab.example.com/issues/\(id)")
        )
    }
}
