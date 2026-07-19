import Foundation

protocol DevRoomMemberServicing: Sendable {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember]
}
