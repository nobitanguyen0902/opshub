import Foundation

struct DevRoomProjectMember: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
    let accessLevel: Int

    var accessLevelTitle: String {
        switch accessLevel {
        case 50...: "Owner"
        case 40..<50: "Maintainer"
        case 30..<40: "Developer"
        case 20..<30: "Reporter"
        case 10..<20: "Guest"
        default: "Minimal access"
        }
    }
}
