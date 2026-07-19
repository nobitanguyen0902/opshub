import Foundation

enum DevRoomChibiSkinTone: Int, CaseIterable, Sendable {
    case light
    case warm
    case tan
    case deep
}

enum DevRoomChibiHairStyle: Int, CaseIterable, Sendable {
    case cropped
    case sidePart
    case wavy
    case bob
    case bun
    case flatTop
}

enum DevRoomChibiHairColor: Int, CaseIterable, Sendable {
    case charcoal
    case black
    case brown
    case auburn
}

enum DevRoomChibiShirtColor: Int, CaseIterable, Sendable {
    case blue
    case green
    case orange
    case purple
    case rose
    case teal
}

enum DevRoomChibiAccessory: Int, CaseIterable, Sendable {
    case none
    case glasses
    case headphones
}

struct DevRoomChibiProfile: Equatable, Sendable {
    let skinTone: DevRoomChibiSkinTone
    let hairStyle: DevRoomChibiHairStyle
    let hairColor: DevRoomChibiHairColor
    let shirtColor: DevRoomChibiShirtColor
    let accessory: DevRoomChibiAccessory
}

struct DevRoomChibiProfileStore: Sendable {
    let curatedByUserID: [Int: DevRoomChibiProfile]
    let curatedByUsername: [String: DevRoomChibiProfile]

    static let production = DevRoomChibiProfileStore()

    init(
        curatedByUserID: [Int: DevRoomChibiProfile] = [:],
        curatedByUsername: [String: DevRoomChibiProfile] = [:]
    ) {
        self.curatedByUserID = curatedByUserID
        self.curatedByUsername = Dictionary(
            uniqueKeysWithValues: curatedByUsername.map { ($0.key.lowercased(), $0.value) }
        )
    }

    func profile(for employee: DevRoomEmployee) -> DevRoomChibiProfile {
        if let profile = curatedByUserID[employee.id] {
            return profile
        }
        if let username = employee.username?.lowercased(),
           let profile = curatedByUsername[username] {
            return profile
        }
        return fallback(employeeID: employee.id)
    }

    private func fallback(employeeID: Int) -> DevRoomChibiProfile {
        let value = employeeID.magnitude
        func index(divisor: UInt, count: Int) -> Int {
            Int((value / divisor) % UInt(count))
        }

        return DevRoomChibiProfile(
            skinTone: DevRoomChibiSkinTone.allCases[
                index(divisor: 1, count: DevRoomChibiSkinTone.allCases.count)
            ],
            hairStyle: DevRoomChibiHairStyle.allCases[
                index(divisor: 3, count: DevRoomChibiHairStyle.allCases.count)
            ],
            hairColor: DevRoomChibiHairColor.allCases[
                index(divisor: 5, count: DevRoomChibiHairColor.allCases.count)
            ],
            shirtColor: DevRoomChibiShirtColor.allCases[
                index(divisor: 7, count: DevRoomChibiShirtColor.allCases.count)
            ],
            accessory: DevRoomChibiAccessory.allCases[
                index(divisor: 11, count: DevRoomChibiAccessory.allCases.count)
            ]
        )
    }
}
