### Task 4: Flat Chibi profile domain and deterministic resolver

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift`
- Create: `Tests/OpsHubTests/DevRoomChibiProfileTests.swift`

**Interfaces:**
- Consumes: `DevRoomEmployee.id`, `.name`, `.username` từ `DevRoomModels.swift`.
- Produces: `DevRoomChibiProfileStore.production.profile(for:) -> DevRoomChibiProfile` cho `DevRoomCharacterView` ở Task 5.

- [ ] **Step 1: Viết failing tests cho curated profile và fallback ổn định**

```swift
import XCTest
@testable import OpsHub

final class DevRoomChibiProfileTests: XCTestCase {
    func testCuratedEmployeeUsesMappedProfile() {
        let expected = DevRoomChibiProfile(
            skinTone: .warm,
            hairStyle: .cropped,
            hairColor: .charcoal,
            shirtColor: .blue,
            accessory: .glasses
        )
        let store = DevRoomChibiProfileStore(curatedByUserID: [11: expected])
        let employee = DevRoomEmployee(
            id: 11,
            name: "Anh Thái Nguyễn",
            username: "thai.nguyen",
            avatarURL: nil
        )

        let profile = store.profile(for: employee)

        XCTAssertEqual(profile, expected)
    }

    func testFallbackIsStableForSameEmployeeID() {
        let first = DevRoomEmployee(id: 999, name: "New User", username: nil, avatarURL: nil)
        let renamed = DevRoomEmployee(id: 999, name: "Renamed User", username: nil, avatarURL: nil)

        XCTAssertEqual(
            DevRoomChibiProfileStore.production.profile(for: first),
            DevRoomChibiProfileStore.production.profile(for: renamed)
        )
    }

    func testFallbackVariesAcrossEmployeeIDs() {
        let first = DevRoomEmployee(id: 999, name: "A", username: nil, avatarURL: nil)
        let second = DevRoomEmployee(id: 1000, name: "B", username: nil, avatarURL: nil)

        XCTAssertNotEqual(
            DevRoomChibiProfileStore.production.profile(for: first),
            DevRoomChibiProfileStore.production.profile(for: second)
        )
    }
}
```

- [ ] **Step 2: Chạy test để xác nhận fail vì profile types chưa tồn tại**

Run:

```bash
swift test --filter DevRoomChibiProfileTests
```

Expected: build fail với `cannot find 'DevRoomChibiProfileStore' in scope`.

- [ ] **Step 3: Implement token model không phụ thuộc SwiftUI Color**

```swift
import Foundation

enum DevRoomChibiSkinTone: Int, CaseIterable, Sendable {
    case light, warm, tan, deep
}

enum DevRoomChibiHairStyle: Int, CaseIterable, Sendable {
    case cropped, sidePart, wavy, bob, bun, flatTop
}

enum DevRoomChibiHairColor: Int, CaseIterable, Sendable {
    case charcoal, black, brown, auburn
}

enum DevRoomChibiShirtColor: Int, CaseIterable, Sendable {
    case blue, green, orange, purple, rose, teal
}

enum DevRoomChibiAccessory: Int, CaseIterable, Sendable {
    case none, glasses, headphones
}

struct DevRoomChibiProfile: Equatable, Sendable {
    let skinTone: DevRoomChibiSkinTone
    let hairStyle: DevRoomChibiHairStyle
    let hairColor: DevRoomChibiHairColor
    let shirtColor: DevRoomChibiShirtColor
    let accessory: DevRoomChibiAccessory
}
```

- [ ] **Step 4: Implement curated mapping theo GitLab ID/username và ID fallback**

Resolver ưu tiên GitLab user ID, sau đó username lowercase. Không dùng display name làm key. `production` là nơi thêm mapping thật khi ID/username đã được xác nhận từ member list; user chưa có mapping dùng fallback chỉ dựa vào ID.

```swift
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
            skinTone: DevRoomChibiSkinTone.allCases[index(divisor: 1, count: DevRoomChibiSkinTone.allCases.count)],
            hairStyle: DevRoomChibiHairStyle.allCases[index(divisor: 3, count: DevRoomChibiHairStyle.allCases.count)],
            hairColor: DevRoomChibiHairColor.allCases[index(divisor: 5, count: DevRoomChibiHairColor.allCases.count)],
            shirtColor: DevRoomChibiShirtColor.allCases[index(divisor: 7, count: DevRoomChibiShirtColor.allCases.count)],
            accessory: DevRoomChibiAccessory.allCases[index(divisor: 11, count: DevRoomChibiAccessory.allCases.count)]
        )
    }
}
```

Không thay `employeeID.magnitude` bằng `abs(employeeID)` vì `Int.min` sẽ overflow.

- [ ] **Step 5: Chạy profile tests và full Dev Room tests**

```bash
swift test --filter DevRoomChibiProfileTests
swift test --filter DevRoom
```

Expected: profile tests pass; toàn bộ Dev Room test hiện có tiếp tục pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift Tests/OpsHubTests/DevRoomChibiProfileTests.swift
git commit -m "feat(dev-room): add flat chibi profiles"
```

---

