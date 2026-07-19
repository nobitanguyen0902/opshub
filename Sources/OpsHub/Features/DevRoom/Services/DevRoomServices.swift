import Foundation

protocol DevRoomServicing: Sendable {
    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue]
}
