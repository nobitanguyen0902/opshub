import Foundation

protocol SprintDashboardServicing: Sendable {
    func sprintMilestones(projectPath: String) async throws -> [SprintMilestone]

    func sprintIssues(
        projectPath: String,
        milestoneTitle: String
    ) async throws -> [SprintDashboardIssue]

    func productionBugs(
        projectPath: String,
        createdAfter: Date,
        createdBefore: Date
    ) async throws -> [SprintDashboardIssue]
}
