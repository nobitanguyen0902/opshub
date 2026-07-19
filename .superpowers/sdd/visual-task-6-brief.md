### Task 6: Shared office background, simple employee tag and workstation

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomOfficeBackground.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeTag.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkstation.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`
- Delete: `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`

**Interfaces:**
- Consumes: `DevRoomEmployeeSummary`, `DevRoomAnimationEvent`, `DevRoomCharacterView(employee:isActive:reduceMotion:)`.
- Produces: `DevRoomWorkstation(summary:animationEvent:isWindowActive:reduceMotion:onSelect:)` cho office grid Task 8.

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

Thêm `@State private var laptopGlow = false` và task lifecycle:

```swift
private var idleAnimationKey: Bool {
    isWindowActive && reduceMotion == false
}

.task(id: idleAnimationKey) {
    guard idleAnimationKey else {
        laptopGlow = false
        return
    }
    do {
        try await Task.sleep(for: .milliseconds(Int(summary.employee.id.magnitude % 600)))
        while Task.isCancelled == false {
            withAnimation(.easeInOut(duration: 0.45)) { laptopGlow.toggle() }
            try await Task.sleep(for: .milliseconds(900))
        }
    } catch {
        laptopGlow = false
    }
}
```

Laptop layer dùng `.opacity(laptopGlow ? 1 : 0.78)`. Khi inactive/Reduce Motion, task bị cancel và reset.

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

