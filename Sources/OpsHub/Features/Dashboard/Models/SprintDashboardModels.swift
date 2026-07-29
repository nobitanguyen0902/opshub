import Foundation

struct SprintMilestone: Identifiable, Hashable, Sendable {
    let id: Int
    let title: String
    let startDate: Date
    let dueDate: Date
}

struct SprintDashboardMember: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let username: String?
    let avatarURL: URL?
}

struct SprintDashboardIssue: Identifiable, Hashable, Sendable {
    let id: Int
    let iid: Int
    let title: String
    let project: String
    let labels: [String]
    let assignee: SprintDashboardMember?
    let createdAt: Date?
    let updatedAt: Date?
    let webURL: URL?
}

struct SprintDashboardMemberSummary: Identifiable, Hashable, Sendable {
    let member: SprintDashboardMember?
    let ticketCount: Int
    let releasedCount: Int

    var id: String {
        member.map { "member:\($0.id)" } ?? "unassigned"
    }

    var progress: Double {
        guard ticketCount > 0 else { return 0 }
        return Double(releasedCount) / Double(ticketCount)
    }
}

struct SprintDashboardData: Equatable, Sendable {
    let milestone: SprintMilestone
    let ticketCount: Int
    let releasedCount: Int
    let productionBugCount: Int
    let memberSummaries: [SprintDashboardMemberSummary]
    let productionBugPreview: [SprintDashboardIssue]
}

enum SprintDashboardAggregator {
    private static let releaseLabels: Set<String> = [
        "passed",
        "toproduction",
        "merged"
    ]

    static func currentMilestone(
        from milestones: [SprintMilestone],
        now: Date,
        calendar: Calendar
    ) -> SprintMilestone? {
        milestones
            .filter { milestone in
                let boundary = sprintBoundary(for: milestone, calendar: calendar)
                return now >= boundary.start && now < boundary.endExclusive
            }
            .max { lhs, rhs in
                let lhsStart = calendar.startOfDay(for: lhs.startDate)
                let rhsStart = calendar.startOfDay(for: rhs.startDate)
                if lhsStart != rhsStart {
                    return lhsStart < rhsStart
                }
                return lhs.id < rhs.id
            }
    }

    static func makeData(
        milestone: SprintMilestone,
        sprintIssues: [SprintDashboardIssue],
        productionBugs: [SprintDashboardIssue],
        selectedUserIDs: Set<Int>,
        calendar: Calendar
    ) -> SprintDashboardData {
        let uniqueSprintIssues = deduplicated(sprintIssues)
        let uniqueProductionBugs = deduplicated(productionBugs)
        let validProductionBugs = validProductionBugs(
            uniqueProductionBugs,
            milestone: milestone,
            calendar: calendar
        )

        return SprintDashboardData(
            milestone: milestone,
            ticketCount: uniqueSprintIssues.count,
            releasedCount: uniqueSprintIssues.count(where: isReleased),
            productionBugCount: validProductionBugs.count,
            memberSummaries: memberSummaries(
                from: uniqueSprintIssues,
                selectedUserIDs: selectedUserIDs
            ),
            productionBugPreview: Array(
                validProductionBugs
                    .sorted(by: issueDateSort)
                    .prefix(5)
            )
        )
    }

    static func sprintBoundary(
        for milestone: SprintMilestone,
        calendar: Calendar
    ) -> (start: Date, endExclusive: Date) {
        let start = calendar.startOfDay(for: milestone.startDate)
        let dueDateStart = calendar.startOfDay(for: milestone.dueDate)
        let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: dueDateStart
        ) ?? dueDateStart
        return (start, endExclusive)
    }

    static func isReleased(_ issue: SprintDashboardIssue) -> Bool {
        let labels = Set(issue.labels.map(normalizedLabel))
        return releaseLabels.isSubset(of: labels)
    }

    private static func validProductionBugs(
        _ issues: [SprintDashboardIssue],
        milestone: SprintMilestone,
        calendar: Calendar
    ) -> [SprintDashboardIssue] {
        let boundary = sprintBoundary(for: milestone, calendar: calendar)
        return issues.filter { issue in
            guard let createdAt = issue.createdAt else { return false }
            let labels = Set(issue.labels.map(normalizedLabel))
            return labels.contains("bug production")
                && createdAt >= boundary.start
                && createdAt < boundary.endExclusive
        }
    }

    private static func memberSummaries(
        from issues: [SprintDashboardIssue],
        selectedUserIDs: Set<Int>
    ) -> [SprintDashboardMemberSummary] {
        let selectedIssues = issues.filter { issue in
            guard let member = issue.assignee else { return true }
            return selectedUserIDs.contains(member.id)
        }
        let assignedIssues = selectedIssues.compactMap { issue -> (SprintDashboardMember, SprintDashboardIssue)? in
            guard let member = issue.assignee else { return nil }
            return (member, issue)
        }
        let groupedIssues = Dictionary(grouping: assignedIssues, by: { $0.0.id })
        var summaries = groupedIssues.values.compactMap { memberIssues -> SprintDashboardMemberSummary? in
            guard let member = memberIssues.first?.0 else { return nil }
            let issues = memberIssues.map(\.1)
            return SprintDashboardMemberSummary(
                member: member,
                ticketCount: issues.count,
                releasedCount: issues.count(where: isReleased)
            )
        }
        .sorted { lhs, rhs in
            guard let lhsMember = lhs.member, let rhsMember = rhs.member else {
                return lhs.member != nil
            }
            let comparison = lhsMember.name.localizedCaseInsensitiveCompare(rhsMember.name)
            if comparison == .orderedSame {
                return lhsMember.id < rhsMember.id
            }
            return comparison == .orderedAscending
        }

        let unassignedIssues = selectedIssues.filter { $0.assignee == nil }
        if unassignedIssues.isEmpty == false {
            summaries.append(
                SprintDashboardMemberSummary(
                    member: nil,
                    ticketCount: unassignedIssues.count,
                    releasedCount: unassignedIssues.count(where: isReleased)
                )
            )
        }
        return summaries
    }

    private static func deduplicated(
        _ issues: [SprintDashboardIssue]
    ) -> [SprintDashboardIssue] {
        Array(
            Dictionary(
                issues.map { ($0.id, $0) },
                uniquingKeysWith: preferredIssue
            ).values
        )
    }

    private static func preferredIssue(
        _ lhs: SprintDashboardIssue,
        _ rhs: SprintDashboardIssue
    ) -> SprintDashboardIssue {
        guard lhs.updatedAt != rhs.updatedAt else { return lhs }
        return (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
            ? lhs
            : rhs
    }

    private static func issueDateSort(
        _ lhs: SprintDashboardIssue,
        _ rhs: SprintDashboardIssue
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        return lhs.id > rhs.id
    }

    private static func normalizedLabel(_ label: String) -> String {
        label
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
