import XCTest
@testable import OpsHub

final class DevRoomChibiProfileTests: XCTestCase {
    func testCuratedProfileByUserIDTakesPrecedenceOverUsername() {
        let byID = profile(
            skinTone: .warm,
            hairStyle: .cropped,
            hairColor: .charcoal,
            shirtColor: .blue,
            accessory: .glasses
        )
        let byUsername = profile(
            skinTone: .deep,
            hairStyle: .bun,
            hairColor: .auburn,
            shirtColor: .rose,
            accessory: .headphones
        )
        let store = DevRoomChibiProfileStore(
            curatedByUserID: [11: byID],
            curatedByUsername: ["thai.nguyen": byUsername]
        )
        let employee = DevRoomEmployee(
            id: 11,
            name: "Anh Thái Nguyễn",
            username: "THAI.NGUYEN",
            avatarURL: nil
        )

        XCTAssertEqual(store.profile(for: employee), byID)
    }

    func testCuratedProfileFallsBackToCaseInsensitiveUsername() {
        let expected = profile(
            skinTone: .tan,
            hairStyle: .wavy,
            hairColor: .brown,
            shirtColor: .teal,
            accessory: .headphones
        )
        let store = DevRoomChibiProfileStore(curatedByUsername: ["alice": expected])
        let employee = DevRoomEmployee(id: 11, name: "Alice Nguyen", username: "ALICE", avatarURL: nil)

        XCTAssertEqual(store.profile(for: employee), expected)
    }

    func testCaseInsensitiveUsernameCollisionUsesLexicographicallyFirstOriginalKey() {
        let uppercaseProfile = profile(
            skinTone: .warm,
            hairStyle: .sidePart,
            hairColor: .brown,
            shirtColor: .blue,
            accessory: .glasses
        )
        let lowercaseProfile = profile(
            skinTone: .deep,
            hairStyle: .bun,
            hairColor: .auburn,
            shirtColor: .rose,
            accessory: .headphones
        )
        let store = DevRoomChibiProfileStore(
            curatedByUsername: [
                "alice": lowercaseProfile,
                "ALICE": uppercaseProfile
            ]
        )
        let employee = DevRoomEmployee(id: 11, name: "Alice Nguyen", username: "Alice", avatarURL: nil)

        XCTAssertEqual(store.profile(for: employee), uppercaseProfile)
    }

    func testDisplayNameNeverResolvesCuratedProfile() {
        let usernameProfile = profile(
            skinTone: .deep,
            hairStyle: .flatTop,
            hairColor: .black,
            shirtColor: .purple,
            accessory: .none
        )
        let store = DevRoomChibiProfileStore(curatedByUsername: ["alice.nguyen": usernameProfile])
        let employee = DevRoomEmployee(id: 999, name: "alice.nguyen", username: nil, avatarURL: nil)

        XCTAssertNotEqual(store.profile(for: employee), usernameProfile)
    }

    func testFallbackIsStableForSameEmployeeIDWhenIdentityFieldsChange() {
        let first = DevRoomEmployee(id: 999, name: "New User", username: nil, avatarURL: nil)
        let renamed = DevRoomEmployee(id: 999, name: "Renamed User", username: "renamed", avatarURL: nil)

        XCTAssertEqual(
            DevRoomChibiProfileStore.production.profile(for: first),
            DevRoomChibiProfileStore.production.profile(for: renamed)
        )
    }

    func testFallbackVariesAcrossEmployeeIDs() {
        let first = DevRoomEmployee(id: 999, name: "A", username: nil, avatarURL: nil)
        let second = DevRoomEmployee(id: 1_000, name: "B", username: nil, avatarURL: nil)

        XCTAssertNotEqual(
            DevRoomChibiProfileStore.production.profile(for: first),
            DevRoomChibiProfileStore.production.profile(for: second)
        )
    }

    func testFallbackProfilesCoverAllSupportedCharacterTraits() {
        let profiles = (0..<2_000).map { employeeID in
            DevRoomChibiProfileStore.production.profile(
                for: DevRoomEmployee(
                    id: employeeID,
                    name: "Employee \(employeeID)",
                    username: nil,
                    avatarURL: nil
                )
            )
        }

        XCTAssertEqual(Set(profiles.map(\.skinTone)), Set(DevRoomChibiSkinTone.allCases))
        XCTAssertEqual(Set(profiles.map(\.hairStyle)), Set(DevRoomChibiHairStyle.allCases))
        XCTAssertEqual(Set(profiles.map(\.hairColor)), Set(DevRoomChibiHairColor.allCases))
        XCTAssertEqual(Set(profiles.map(\.shirtColor)), Set(DevRoomChibiShirtColor.allCases))
        XCTAssertEqual(Set(profiles.map(\.accessory)), Set(DevRoomChibiAccessory.allCases))
    }

    private func profile(
        skinTone: DevRoomChibiSkinTone,
        hairStyle: DevRoomChibiHairStyle,
        hairColor: DevRoomChibiHairColor,
        shirtColor: DevRoomChibiShirtColor,
        accessory: DevRoomChibiAccessory
    ) -> DevRoomChibiProfile {
        DevRoomChibiProfile(
            skinTone: skinTone,
            hairStyle: hairStyle,
            hairColor: hairColor,
            shirtColor: shirtColor,
            accessory: accessory
        )
    }
}
