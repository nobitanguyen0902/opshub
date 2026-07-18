### Task 1: Workflow domain và room aggregation

**Files:**
- Create: Sources/OpsHub/Features/GitLab/Models/GitLabWorkflowProject.swift
- Create: Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift
- Test: Tests/OpsHubTests/DevRoomAggregationTests.swift

**Interfaces:**
- Consumes: Không có dependency từ task khác.
- Produces:
  - GitLabWorkflowProject.path: String
  - DevRoomWorkflowStage.stage(for: [String]) -> DevRoomWorkflowStage?
  - DevRoomSourceIssue
  - DevRoomEmployee
  - DevRoomIssue
  - DevRoomEmployeeSummary
  - DevRoomData
  - DevRoomAggregator.makeData(from:) -> DevRoomData

- [ ] **Step 1: Viết failing tests cho label precedence, assignee filtering và aggregation**

Tạo Tests/OpsHubTests/DevRoomAggregationTests.swift:

~~~swift
import Foundation
import XCTest
@testable import OpsHub

final class DevRoomAggregationTests: XCTestCase {
    func testStageMatchingNormalizesCaseAndWhitespace() {
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" TODO "]), .todo)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["doing"]), .doing)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["toTEST"]), .toTest)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: [" test "]), .test)
        XCTAssertEqual(DevRoomWorkflowStage.stage(for: ["PASSED"]), .passed)
    }

    func testMultipleWorkflowLabelsUseFurthestStage() {
        XCTAssertEqual(
            DevRoomWorkflowStage.stage(for: ["Doing", "Todo", "Test"]),
            .test
        )
    }

    func testAggregationExcludesUnassignedAndNonWorkflowIssues() {
        let alice = employee(id: 1, name: "Alice")
        let sources = [
            source(id: 1, labels: ["Doing"], assignee: alice),
            source(id: 2, labels: ["Backend"], assignee: alice),
            source(id: 3, labels: ["Test"], assignee: nil)
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

    func testPreviewUsesTwoMostRecentlyUpdatedIssues() {
        let alice = employee(id: 1, name: "Alice")
        let sources = [
            source(id: 1, title: "Old", labels: ["Todo"], assignee: alice, updatedAt: Date(timeIntervalSince1970: 1)),
            source(id: 2, title: "Newest", labels: ["Doing"], assignee: alice, updatedAt: Date(timeIntervalSince1970: 3)),
            source(id: 3, title: "Middle", labels: ["Test"], assignee: alice, updatedAt: Date(timeIntervalSince1970: 2))
        ]

        let data = DevRoomAggregator.makeData(from: sources)

        XCTAssertEqual(data.employees[0].previewIssues.map(\.title), ["Newest", "Middle"])
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
~~~

- [ ] **Step 2: Chạy test và xác nhận fail vì domain chưa tồn tại**

Run:

~~~bash
swift test --filter DevRoomAggregationTests
~~~

Expected: build FAIL với lỗi không tìm thấy DevRoomWorkflowStage hoặc DevRoomAggregator.

- [ ] **Step 3: Thêm Project constant và domain implementation tối thiểu**

Tạo Sources/OpsHub/Features/GitLab/Models/GitLabWorkflowProject.swift:

~~~swift
enum GitLabWorkflowProject {
    static let path = "social/socom-issues"
}
~~~

Tạo Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift:

~~~swift
import Foundation

enum DevRoomWorkflowStage: Int, CaseIterable, Identifiable, Hashable, Sendable {
    case todo
    case doing
    case toTest
    case test
    case passed

    var id: Self { self }

    var title: String {
        switch self {
        case .todo: "Todo"
        case .doing: "Doing"
        case .toTest: "ToTest"
        case .test: "Test"
        case .passed: "Passed"
        }
    }

    static func stage(for labels: [String]) -> Self? {
        let stages = labels.compactMap { label -> Self? in
            switch label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "todo": .todo
            case "doing": .doing
            case "totest": .toTest
            case "test": .test
            case "passed": .passed
            default: nil
            }
        }
        return stages.max(by: { $0.rawValue < $1.rawValue })
    }
}

struct DevRoomEmployee: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let username: String?
    let avatarURL: URL?
}

struct DevRoomSourceIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let labels: [String]
    let assignee: DevRoomEmployee?
    let updatedAt: Date?
    let webURL: URL?
}

struct DevRoomIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let stage: DevRoomWorkflowStage
    let assignee: DevRoomEmployee
    let updatedAt: Date?
    let webURL: URL?
}

struct DevRoomEmployeeSummary: Identifiable, Hashable, Sendable {
    let employee: DevRoomEmployee
    let issues: [DevRoomIssue]

    var id: Int { employee.id }
    var total: Int { issues.count }
    var previewIssues: [DevRoomIssue] { Array(issues.prefix(2)) }

    func count(for stage: DevRoomWorkflowStage) -> Int {
        issues.count { $0.stage == stage }
    }

    func previewIssues(for selectedStage: DevRoomWorkflowStage?) -> [DevRoomIssue] {
        guard let selectedStage else { return previewIssues }
        return Array(issues.filter { $0.stage == selectedStage }.prefix(2))
    }
}

struct DevRoomData: Equatable, Sendable {
    let issues: [DevRoomIssue]
    let employees: [DevRoomEmployeeSummary]

    static let empty = DevRoomData(issues: [], employees: [])

    var total: Int { issues.count }

    func count(for stage: DevRoomWorkflowStage) -> Int {
        issues.count { $0.stage == stage }
    }
}

enum DevRoomAggregator {
    static func makeData(from sources: [DevRoomSourceIssue]) -> DevRoomData {
        let issues = sources.compactMap { source -> DevRoomIssue? in
            guard let assignee = source.assignee,
                  let stage = DevRoomWorkflowStage.stage(for: source.labels) else {
                return nil
            }
            return DevRoomIssue(
                id: source.id,
                iid: source.iid,
                title: source.title,
                stage: stage,
                assignee: assignee,
                updatedAt: source.updatedAt,
                webURL: source.webURL
            )
        }
        .sorted(by: issueSort)

        let employees = Dictionary(grouping: issues, by: \.assignee.id)
            .values
            .compactMap { employeeIssues -> DevRoomEmployeeSummary? in
                guard let employee = employeeIssues.first?.assignee else { return nil }
                return DevRoomEmployeeSummary(employee: employee, issues: employeeIssues)
            }
            .sorted {
                let comparison = $0.employee.name.localizedCaseInsensitiveCompare($1.employee.name)
                return comparison == .orderedSame
                    ? $0.employee.id < $1.employee.id
                    : comparison == .orderedAscending
            }

        return DevRoomData(issues: issues, employees: employees)
    }

    private static func issueSort(_ lhs: DevRoomIssue, _ rhs: DevRoomIssue) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        return lhs.id > rhs.id
    }
}
~~~

- [ ] **Step 4: Chạy targeted tests**

Run:

~~~bash
swift test --filter DevRoomAggregationTests
~~~

Expected: toàn bộ DevRoomAggregationTests PASS.

- [ ] **Step 5: Commit domain**

~~~bash
git add Sources/OpsHub/Features/GitLab/Models/GitLabWorkflowProject.swift Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift Tests/OpsHubTests/DevRoomAggregationTests.swift
git commit -m "feat(dev-room): add workflow aggregation domain"
~~~

---

