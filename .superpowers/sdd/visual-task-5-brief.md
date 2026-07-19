### Task 5: Flat Chibi layered character and idle animation

**Files:**
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`

**Interfaces:**
- Consumes: `DevRoomChibiProfileStore.production.profile(for:)` từ Task 4.
- Produces: `DevRoomCharacterView(employee:isActive:reduceMotion:)` cho workstation Task 6.

- [ ] **Step 1: Đổi Character API để nhận toàn bộ employee**

```swift
struct DevRoomCharacterView: View {
    let employee: DevRoomEmployee
    let isActive: Bool
    let reduceMotion: Bool

    private var profile: DevRoomChibiProfile {
        DevRoomChibiProfileStore.production.profile(for: employee)
    }
}
```

Thay mọi phase/delay đang dùng `employeeID` bằng `employee.id`.

- [ ] **Step 2: Thêm palette mapping ở presentation layer**

Trong `DevRoomDesignTokens.swift`, thêm các helper:

```swift
static func skinColor(_ tone: DevRoomChibiSkinTone) -> Color
static func hairColor(_ color: DevRoomChibiHairColor) -> Color
static func shirtColor(_ color: DevRoomChibiShirtColor) -> Color
```

Mapping dùng palette cố định:

```swift
case .light: Color(red: 1.00, green: 0.86, blue: 0.77)
case .warm: Color(red: 0.93, green: 0.73, blue: 0.60)
case .tan: Color(red: 0.77, green: 0.55, blue: 0.40)
case .deep: Color(red: 0.55, green: 0.36, blue: 0.27)
```

Hair dùng charcoal/black/brown/auburn; shirt dùng blue/green/orange/purple/rose/teal. Không dùng stage color làm shirt color.

- [ ] **Step 3: Thay body bằng Flat Chibi layers**

`body` giữ frame cao khoảng `118pt` và gồm:

```swift
ZStack {
    torso
    head
    hair
    eyes
    mouth
    arms
    accessory
}
.frame(width: 126, height: 118)
```

Tách mỗi layer thành `private var` hoặc `@ViewBuilder` property. Hair style phải có sáu switch case; accessory phải có `none`, `glasses`, `headphones`. Không dùng asset ngoài.

- [ ] **Step 4: Giữ animation lifecycle hiện có nhưng áp dụng lên layer mới**

- `isTyping` xoay hai tay tối đa `±4°` và làm thân/head dịch tối đa `2pt`.
- `isBlinking` đổi chiều cao mắt từ `7pt` sang `1pt`.
- Laptop glow không nằm trong Character; Task 6 chạy một phase opacity nhẹ riêng trên workstation, cũng được key bằng employee ID.
- `.task(id: animationKey)` phải reset `isTyping/isBlinking` khi Reduce Motion bật hoặc window inactive.
- Catch `CancellationError` và không tạo task detached/timer.

- [ ] **Step 5: Compile cả Debug và Release**

```bash
swift build
swift build -c release
```

Expected: hai build pass, không warning strict concurrency mới.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift
git commit -m "feat(dev-room): draw layered flat chibi employees"
```

---

