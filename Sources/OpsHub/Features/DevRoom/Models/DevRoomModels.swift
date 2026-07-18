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
        let uniqueSources = Dictionary(
            sources.map { ($0.id, $0) },
            uniquingKeysWith: preferredSource
        ).values
        let issues = uniqueSources.compactMap { source -> DevRoomIssue? in
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

    private static func preferredSource(
        _ lhs: DevRoomSourceIssue,
        _ rhs: DevRoomSourceIssue
    ) -> DevRoomSourceIssue {
        guard lhs.updatedAt != rhs.updatedAt else { return lhs }
        return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast) ? lhs : rhs
    }

    private static func issueSort(_ lhs: DevRoomIssue, _ rhs: DevRoomIssue) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
        return lhs.id > rhs.id
    }
}
