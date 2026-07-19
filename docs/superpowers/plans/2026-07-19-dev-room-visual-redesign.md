# Dev Room Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thay giao diện Dev Room dạng card rời bằng một căn phòng chung có nhiều Flat Chibi đang làm việc, employee tag tối giản và detail drawer trượt từ phải.

**Architecture:** Giữ nguyên service, aggregation, snapshot diff và ViewModel lifecycle. Tách presentation thành profile store thuần dữ liệu, Flat Chibi nhiều layer, workstation, office background và overlay drawer; `DevRoomView` chỉ phối hợp state và layout. Những behavior có thể kiểm thử không cần render được đưa vào model/ViewModel và viết test trước.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, XCTest, SF Symbols; không thêm package, asset raster, Lottie hoặc Rive.

## Global Constraints

- Project tiếp tục là `social/socom-issues`; chỉ đọc GitLab issue `opened` có assignee và workflow label hợp lệ.
- Giữ nguyên thứ tự `Todo → Doing → ToTest → Test → Passed`, pagination, dedupe issue ID, refresh thủ công và auto-refresh hai phút.
- Không thay đổi Dashboard, Brew, GitLab, Settings hoặc top-level navigation.
- Không sửa label, assignee hoặc state GitLab từ Dev Room.
- Room là một office scene chung; không dùng card/container lớn bao quanh từng nhân viên.
- Employee tag chỉ hiển thị avatar, display name, tổng task và stage dot.
- Flat Chibi được dựng bằng SwiftUI layers; profile thủ công có fallback ổn định theo employee ID.
- Drawer rộng khoảng `360pt`, overlay lên Room và không làm workstation grid reflow.
- Reduce Motion và inactive window phải dừng idle/pulse; drawer bỏ animation khi Reduce Motion bật.
- Bảo toàn thay đổi local không liên quan, đặc biệt `.swiftpm/xcode/.../UserInterfaceState.xcuserstate` và `.superpowers/brainstorm/`.

---

## File Structure

### Files tạo mới

- `Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift` — token profile, curated mapping và deterministic fallback.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomOfficeBackground.swift` — tường, sàn, cửa sổ, đồng hồ và cây bằng SwiftUI shape.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeTag.swift` — employee tag tối giản.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkstation.swift` — ghép tag, Flat Chibi, laptop và bàn.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailDrawer.swift` — sidebar overlay và grouped issue detail.
- `Tests/OpsHubTests/DevRoomChibiProfileTests.swift` — curated/fallback profile tests.

### Files sửa

- `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift` — thay hình học hiện tại bằng Flat Chibi nhiều layer.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift` — office palette, room sizing và drawer width.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift` — thu gọn summary strip.
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift` — stage representative và đóng selection khi filter loại nhân viên.
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift` — office scene, responsive grid và overlay drawer.
- `Tests/OpsHubTests/DevRoomViewModelTests.swift` — selection/filter behavior và representative stage.

### Files xóa sau khi thay thế hoàn toàn

- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift`

---

### Task 1: Flat Chibi profile domain and deterministic resolver

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift`
- Create: `Tests/OpsHubTests/DevRoomChibiProfileTests.swift`

**Interfaces:**
- Consumes: `DevRoomEmployee.id`, `.name`, `.username` từ `DevRoomModels.swift`.
- Produces: `DevRoomChibiProfileStore.profile(for:) -> DevRoomChibiProfile` cho `DevRoomCharacterView` ở Task 2.

- [ ] **Step 1: Viết failing tests cho curated profile và fallback ổn định**

```swift
import XCTest
@testable import OpsHub

final class DevRoomChibiProfileTests: XCTestCase {
    func testCuratedEmployeeUsesMappedProfile() {
        let employee = DevRoomEmployee(
            id: 11,
            name: "Anh Thái Nguyễn",
            username: nil,
            avatarURL: nil
        )

        let profile = DevRoomChibiProfileStore.profile(for: employee)

        XCTAssertEqual(profile.hairStyle, .cropped)
        XCTAssertEqual(profile.shirtColor, .blue)
    }

    func testFallbackIsStableForSameEmployeeID() {
        let first = DevRoomEmployee(id: 999, name: "New User", username: nil, avatarURL: nil)
        let renamed = DevRoomEmployee(id: 999, name: "Renamed User", username: nil, avatarURL: nil)

        XCTAssertEqual(
            DevRoomChibiProfileStore.profile(for: first),
            DevRoomChibiProfileStore.profile(for: renamed)
        )
    }

    func testFallbackVariesAcrossEmployeeIDs() {
        let first = DevRoomEmployee(id: 999, name: "A", username: nil, avatarURL: nil)
        let second = DevRoomEmployee(id: 1000, name: "B", username: nil, avatarURL: nil)

        XCTAssertNotEqual(
            DevRoomChibiProfileStore.profile(for: first),
            DevRoomChibiProfileStore.profile(for: second)
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

- [ ] **Step 4: Implement curated mapping và ID fallback**

Resolver ưu tiên current-team mapping theo normalized display name; dictionary vẫn nằm sau API `profile(for:)`, nên có thể đổi key sang GitLab ID/username khi xác nhận được mà không chạm view. Fallback chỉ dùng employee ID.

```swift
enum DevRoomChibiProfileStore {
    static func profile(for employee: DevRoomEmployee) -> DevRoomChibiProfile {
        if let curated = curatedProfiles[normalize(employee.name)] {
            return curated
        }
        return fallback(employeeID: employee.id)
    }

    private static let curatedProfiles: [String: DevRoomChibiProfile] = [
        "anh thai nguyen": .init(skinTone: .warm, hairStyle: .cropped, hairColor: .charcoal, shirtColor: .blue, accessory: .glasses),
        "bui thong ngoc thanh": .init(skinTone: .light, hairStyle: .sidePart, hairColor: .black, shirtColor: .green, accessory: .glasses),
        "cao tien quang": .init(skinTone: .deep, hairStyle: .cropped, hairColor: .black, shirtColor: .purple, accessory: .none),
        "gia han trac": .init(skinTone: .warm, hairStyle: .bun, hairColor: .black, shirtColor: .rose, accessory: .none),
        "kim thanh": .init(skinTone: .light, hairStyle: .wavy, hairColor: .brown, shirtColor: .orange, accessory: .headphones),
        "thanh nguyen van": .init(skinTone: .warm, hairStyle: .sidePart, hairColor: .black, shirtColor: .green, accessory: .none),
        "trinh quoc cuong": .init(skinTone: .warm, hairStyle: .cropped, hairColor: .black, shirtColor: .blue, accessory: .none),
        "van huynh quang": .init(skinTone: .warm, hairStyle: .sidePart, hairColor: .black, shirtColor: .purple, accessory: .none)
    ]

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func fallback(employeeID: Int) -> DevRoomChibiProfile {
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

### Task 2: Flat Chibi layered character and idle animation

**Files:**
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`

**Interfaces:**
- Consumes: `DevRoomChibiProfileStore.profile(for:)` từ Task 1.
- Produces: `DevRoomCharacterView(employee:isActive:reduceMotion:)` cho workstation Task 3.

- [ ] **Step 1: Đổi Character API để nhận toàn bộ employee**

```swift
struct DevRoomCharacterView: View {
    let employee: DevRoomEmployee
    let isActive: Bool
    let reduceMotion: Bool

    private var profile: DevRoomChibiProfile {
        DevRoomChibiProfileStore.profile(for: employee)
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
- Laptop glow không nằm trong Character nữa; Task 3 điều khiển laptop opacity theo phase nếu cần.
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

### Task 3: Shared office background, simple employee tag and workstation

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomOfficeBackground.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeTag.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkstation.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`
- Delete: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`

**Interfaces:**
- Consumes: `DevRoomEmployeeSummary`, `DevRoomAnimationEvent`, `DevRoomCharacterView(employee:isActive:reduceMotion:)`.
- Produces: `DevRoomWorkstation(summary:animationEvent:isWindowActive:reduceMotion:onSelect:)` cho office grid Task 5.

- [ ] **Step 1: Thêm computed representative stage thuần domain**

Trong extension `DevRoomEmployeeSummary` ở `DevRoomModels.swift`:

```swift
var representativeStage: DevRoomWorkflowStage? {
    DevRoomWorkflowStage.allCases.reversed().first { count(for: $0) > 0 }
}
```

Thêm test vào `DevRoomAggregationTests` xác nhận employee có Todo + Test trả `.test`, không dùng số lượng task để chọn stage.

- [ ] **Step 2: Tạo employee tag chỉ có bốn trường visual**

```swift
struct DevRoomEmployeeTag: View {
    let summary: DevRoomEmployeeSummary

    var body: some View {
        HStack(spacing: 8) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.employee.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text("\(summary.total) task").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let stage = summary.representativeStage {
                Circle()
                    .fill(DevRoomDesignTokens.color(for: stage))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
            }
        }
    }
}
```

Không thêm issue preview, five-count strip, role, username hoặc timestamp.

- [ ] **Step 3: Tạo office background bằng SwiftUI shape**

`DevRoomOfficeBackground` là `GeometryReader` + `ZStack` gồm:

- wall fill trên khoảng 28% chiều cao;
- floor fill phần còn lại và line texture opacity dưới `0.06`;
- hai cửa sổ chỉ hiện khi width ≥ `760pt`, một cửa sổ khi nhỏ hơn;
- clock giữa tường;
- tối đa hai plant decoration;
- `.accessibilityHidden(true)` cho toàn background.

Không đặt workstation trong component này và không dùng `Canvas` loop liên tục.

- [ ] **Step 4: Tạo workstation nhiều layer và chuyển pulse logic**

```swift
struct DevRoomWorkstation: View {
    let summary: DevRoomEmployeeSummary
    let animationEvent: DevRoomAnimationEvent?
    let isWindowActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void
}
```

Body là một `Button` duy nhất chứa `ZStack(alignment: .top)`:

1. `DevRoomEmployeeTag` ở trên;
2. `DevRoomCharacterView` ở giữa;
3. laptop, desk top, desk legs và mug ở dưới.

Chuyển nguyên generation/affected employee pulse cancellation từ `DevRoomEmployeeDesk`. Workstation có:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel("\(summary.employee.name), \(summary.total) task")
.accessibilityHint("Mở danh sách task")
```

- [ ] **Step 5: Xóa component Desk cũ và compile**

```bash
swift build
```

Expected: build pass; search sau không còn call site `DevRoomEmployeeDesk(`.

```bash
rg "DevRoomEmployeeDesk" Sources Tests
```

Expected: không có kết quả.

- [ ] **Step 6: Chạy domain tests và commit**

```bash
swift test --filter DevRoomAggregationTests
git add Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomOfficeBackground.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeTag.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkstation.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift Tests/OpsHubTests/DevRoomAggregationTests.swift
git commit -m "feat(dev-room): compose shared office workstations"
```

---

### Task 4: Overlay detail drawer and selection rules

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailDrawer.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift`
- Modify: `Tests/OpsHubTests/DevRoomViewModelTests.swift`
- Delete: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift`

**Interfaces:**
- Consumes: `selectedEmployee`, `selectedStage`, `selectEmployee(_:)`, `DevRoomEmployeeSummary`.
- Produces: drawer content và ViewModel rule tự đóng selection khi filter loại employee.

- [ ] **Step 1: Viết failing tests cho filter-selection behavior**

```swift
@MainActor
func testSelectingFilterClosesEmployeeOutsideFilteredRoom() async {
    let service = SequencedDevRoomService(results: [[
        source(id: 1, employeeID: 10, labels: ["Doing"]),
        source(id: 2, employeeID: 20, labels: ["Test"])
    ]])
    let viewModel = DevRoomViewModel(service: service)
    await viewModel.refresh()
    viewModel.selectEmployee(10)

    viewModel.toggleStage(.test)

    XCTAssertNil(viewModel.selectedEmployeeID)
}

@MainActor
func testSelectingFilterKeepsEmployeeInsideFilteredRoom() async {
    let service = SequencedDevRoomService(results: [[
        source(id: 1, employeeID: 10, labels: ["Doing"])
    ]])
    let viewModel = DevRoomViewModel(service: service)
    await viewModel.refresh()
    viewModel.selectEmployee(10)

    viewModel.toggleStage(.doing)

    XCTAssertEqual(viewModel.selectedEmployeeID, 10)
}
```

- [ ] **Step 2: Chạy tests để xác nhận case outside filter fail**

```bash
swift test --filter DevRoomViewModelTests/testSelectingFilter
```

Expected: test outside-filter fail vì selection vẫn là `10`.

- [ ] **Step 3: Sửa `toggleStage` và gom selection validity**

```swift
func toggleStage(_ stage: DevRoomWorkflowStage) {
    selectedStage = selectedStage == stage ? nil : stage
    clearSelectionIfHidden()
}

private func clearSelectionIfHidden() {
    guard let selectedEmployeeID else { return }
    if displayedEmployees.contains(where: { $0.id == selectedEmployeeID }) == false {
        self.selectedEmployeeID = nil
    }
}
```

Sau refresh thành công cũng gọi `clearSelectionIfHidden()` thay cho check trực tiếp trên `data.employees`, để filter và refresh dùng cùng rule.

- [ ] **Step 4: Tạo drawer content mới**

```swift
struct DevRoomEmployeeDetailDrawer: View {
    @Environment(\.openURL) private var openURL
    let summary: DevRoomEmployeeSummary
    let preferredStage: DevRoomWorkflowStage?
    let onClose: () -> Void
}
```

Drawer gồm:

- header avatar/name/username/total + nút xmark;
- five-count compact summary;
- ScrollView group issue theo `orderedStages`;
- mỗi issue button có `#iid`, title, formatted `updatedAt`, stage badge;
- disabled nếu `webURL == nil`;
- `.accessibilityElement(children: .contain)` trên drawer và focus heading bằng `@AccessibilityFocusState` khi drawer xuất hiện.

- [ ] **Step 5: Xóa panel cũ, chạy tests và compile**

```bash
swift test --filter DevRoomViewModelTests
swift build
rg "DevRoomEmployeeDetailPanel" Sources Tests
```

Expected: tests/build pass; `rg` không còn kết quả.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailDrawer.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift Tests/OpsHubTests/DevRoomViewModelTests.swift
git commit -m "feat(dev-room): add overlay employee detail drawer"
```

---

### Task 5: Integrate responsive office scene and overlay presentation

**Files:**
- Modify: `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`

**Interfaces:**
- Consumes: `DevRoomOfficeBackground`, `DevRoomWorkstation`, `DevRoomEmployeeDetailDrawer`, ViewModel selection/filter state.
- Produces: hoàn chỉnh shared-office screen và drawer transition.

- [ ] **Step 1: Thu gọn workflow summary**

- Giảm minHeight từ `72` xuống khoảng `56`.
- Giảm vertical spacing/padding nhưng giữ năm cột, stage title, count, selected border và accessibility selected trait.
- Stage title dùng `.lineLimit(1)` và `.minimumScaleFactor(0.8)` ở width hẹp; không đổi thành horizontal scroll.

- [ ] **Step 2: Thay `roomContent` bằng ZStack overlay**

```swift
private var roomContent: some View {
    ZStack(alignment: .trailing) {
        officeContent

        if let employee = viewModel.selectedEmployee {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { viewModel.selectEmployee(nil) }
                .transition(.opacity)

            DevRoomEmployeeDetailDrawer(
                summary: employee,
                preferredStage: viewModel.selectedStage,
                onClose: { viewModel.selectEmployee(nil) }
            )
            .frame(width: DevRoomDesignTokens.drawerWidth)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }
}
```

Không dùng `HStack + Divider`; drawer không được giảm width của office.

- [ ] **Step 3: Tạo office content và responsive grid**

```swift
private var officeContent: some View {
    ScrollView {
        VStack(spacing: DevRoomDesignTokens.sectionSpacing) {
            DevRoomWorkflowSummary(...)
            ZStack(alignment: .top) {
                DevRoomOfficeBackground()
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 24)],
                    spacing: 34
                ) {
                    ForEach(viewModel.displayedEmployees) { employee in
                        DevRoomWorkstation(...)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 112)
                .padding(.bottom, 36)
            }
            .frame(minHeight: 560)
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .padding(DevRoomDesignTokens.pagePadding)
    }
}
```

Room empty state phải nằm trong ZStack office, trên background, và dùng message hiện có theo selected stage.

- [ ] **Step 4: Thêm drawer animation, Escape và Reduce Motion**

- Bọc thay đổi selection bằng `.animation(reduceMotion ? nil : .easeOut(duration: 0.24), value: viewModel.selectedEmployeeID)`.
- Thêm `.onExitCommand { viewModel.selectEmployee(nil) }` trên root ZStack của `roomContent`.
- Khi Reduce Motion bật, drawer xuất hiện/biến mất tức thời.
- Scrim không chặn nút đóng/issue button trong drawer vì nằm dưới drawer trong ZStack.

- [ ] **Step 5: Bảo toàn animation event relay**

Giữ `displayedAnimationEvent` và `.onChange(of: viewModel.animationEvent?.generation)` như code hiện tại. Mỗi `DevRoomWorkstation` nhận cùng event; tự guard `employeeIDs` ở bên trong. Không truyền trực tiếp `viewModel.animationEvent` nếu điều đó làm employee mới bỏ lỡ generation relay.

- [ ] **Step 6: Chạy targeted tests, full tests và builds**

```bash
swift test --filter DevRoom
swift test
swift build
swift build -c release
git diff --check
```

Expected: toàn bộ lệnh pass; test count không thấp hơn baseline hiện tại `106` cộng các test mới.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift
git commit -m "feat(dev-room): present team in shared office room"
```

---

### Task 6: Visual acceptance, accessibility and regression hardening

**Files:**
- Modify only if acceptance finds a confirmed issue in `Sources/OpsHub/Features/DevRoom/**` or `Tests/OpsHubTests/DevRoom*Tests.swift`.

**Interfaces:**
- Consumes: hoàn chỉnh Dev Room visual redesign từ Tasks 1–5.
- Produces: verified feature ready for review.

- [ ] **Step 1: Static acceptance scan**

```bash
rg "previewIssues|DevRoomEmployeeDesk|DevRoomEmployeeDetailPanel" Sources/OpsHub/Features/DevRoom
```

Expected: không còn issue preview trong Room và không còn hai component cũ.

```bash
rg "DevRoomEmployeeTag|DevRoomWorkstation|DevRoomEmployeeDetailDrawer|DevRoomOfficeBackground" Sources/OpsHub/Features/DevRoom
```

Expected: các component mới có call site từ screen hoàn chỉnh.

- [ ] **Step 2: Chạy focused regression families**

```bash
swift test --filter DevRoom
swift test --filter AppSectionTests
swift test --filter GitLabIssueTabTests
swift test --filter GitLabServiceTests
swift test --filter GitLabDashboardViewModelTests
```

Expected: tất cả pass; GitLab behavior cũ không đổi.

- [ ] **Step 3: Chạy full gates**

```bash
swift test
swift build
swift build -c release
git diff --check
```

Expected: tất cả pass, không warning/error mới.

- [ ] **Step 4: Manual GUI acceptance**

Chạy:

```bash
swift run OpsHub
```

Kiểm tra trên cửa sổ rộng và hẹp:

1. Room trông như một office scene chung, không còn card lớn quanh từng employee.
2. Mỗi workstation chỉ có avatar, name, total task và stage dot.
3. Flat Chibi hiện khác tóc/da/áo/phụ kiện theo curated profile; employee chưa map vẫn có profile ổn định.
4. Chibi gõ phím/chớp mắt lệch nhịp; window inactive và Reduce Motion dừng animation.
5. Click tag/chibi/laptop/desk đều mở đúng employee drawer.
6. Drawer slide từ phải và overlay lên Room; grid không reflow.
7. Nút xmark, click scrim và Escape đều đóng drawer.
8. Click issue mở GitLab bằng browser mặc định.
9. Workflow filter vẫn đúng; selection bị loại khỏi filter thì drawer đóng.
10. Refresh và task-change pulse chỉ tác động employee phù hợp.

Không để process GUI chạy nền sau acceptance.

- [ ] **Step 5: Fix confirmed acceptance issues minimally and rerun covering gates**

Mỗi fix phải có regression test ở model/ViewModel nếu behavior có seam testable. Không thêm snapshot-test dependency hoặc refactor ngoài Dev Room.

- [ ] **Step 6: Final diff review and commit if Task 6 changed code**

```bash
git diff --stat 88b9226..HEAD
git diff 88b9226..HEAD -- Sources/OpsHub/Features/DevRoom Tests/OpsHubTests
```

Nếu có fix ở Task 6:

```bash
git add Sources/OpsHub/Features/DevRoom Tests/OpsHubTests
git commit -m "fix(dev-room): finalize shared office presentation"
```

Không stage `.swiftpm/xcode/.../UserInterfaceState.xcuserstate` hoặc `.superpowers/brainstorm/`.

---

## Final Review Gate

Sau Task 6:

1. Dùng `superpowers:requesting-code-review` để review range `88b9226..HEAD`.
2. Reviewer phải kiểm tra spec `docs/superpowers/specs/2026-07-19-dev-room-visual-redesign-design.md`, cancellation/lifecycle animation, accessibility, responsive room và không regression GitLab.
3. Fix toàn bộ Critical/Important findings bằng một task riêng, chạy lại targeted/full gates và re-review.
4. Không push hoặc tạo PR nếu user chưa yêu cầu.
