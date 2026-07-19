### Task 7: Nhân vật và animation mức 1

**Files:**
- Create: Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift
- Modify: Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift
- Modify: Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift
- Modify: Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift

**Interfaces:**
- Consumes: employee ID, DevRoomAnimationEvent, accessibilityReduceMotion, controlActiveState.
- Produces:
  - DevRoomCharacterView(employeeID:isActive:reduceMotion:)
  - Employee desk pulse chỉ khi event generation thay đổi và employee nằm trong employeeIDs.

- [ ] **Step 1: Implement layered character with deterministic phase**

Tạo DevRoomCharacterView.swift:

~~~swift
import SwiftUI

struct DevRoomCharacterView: View {
    let employeeID: Int
    let isActive: Bool
    let reduceMotion: Bool

    @State private var isTyping = false
    @State private var isBlinking = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 110, height: 50)
                .offset(y: 34)

            Circle()
                .fill(characterColor.opacity(0.22))
                .frame(width: 54, height: 54)
                .offset(y: -20)
                .overlay {
                    HStack(spacing: 12) {
                        Capsule().frame(width: 4, height: isBlinking ? 1 : 5)
                        Capsule().frame(width: 4, height: isBlinking ? 1 : 5)
                    }
                    .offset(y: -20)
                }

            Image(systemName: "laptopcomputer")
                .font(.system(size: 48))
                .offset(y: 28)

            HStack(spacing: 26) {
                Capsule()
                Capsule()
            }
            .foregroundStyle(characterColor)
            .frame(width: 72, height: 12)
            .rotationEffect(.degrees(isTyping ? 3 : -3))
            .offset(y: 23)
        }
        .frame(height: 130)
        .task(id: animationKey) {
            guard animationKey else {
                isTyping = false
                isBlinking = false
                return
            }
            try? await Task.sleep(for: .milliseconds(employeeID % 700))
            while Task.isCancelled == false {
                withAnimation(.easeInOut(duration: 0.35)) { isTyping.toggle() }
                try? await Task.sleep(for: .milliseconds(700 + employeeID % 500))
                withAnimation(.linear(duration: 0.08)) { isBlinking = true }
                try? await Task.sleep(for: .milliseconds(120))
                withAnimation(.linear(duration: 0.08)) { isBlinking = false }
            }
        }
    }

    private var animationKey: Bool {
        isActive && reduceMotion == false
    }

    private var characterColor: Color {
        [.blue, .green, .orange, .purple][abs(employeeID) % 4]
    }
}
~~~

- [ ] **Step 2: Wire character and task-change pulse into employee desk**

Đổi interface:

~~~swift
struct DevRoomEmployeeDesk: View {
    let summary: DevRoomEmployeeSummary
    let selectedStage: DevRoomWorkflowStage?
    let animationEvent: DevRoomAnimationEvent?
    let isWindowActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    @State private var pulse = false
}
~~~

Thay desk placeholder bằng:

~~~swift
DevRoomCharacterView(
    employeeID: summary.employee.id,
    isActive: isWindowActive,
    reduceMotion: reduceMotion
)
~~~

Thêm event reaction:

~~~swift
.scaleEffect(pulse ? 1.025 : 1)
.onChange(of: animationEvent?.generation) {
    guard reduceMotion == false,
          animationEvent?.employeeIDs.contains(summary.employee.id) == true else {
        return
    }
    withAnimation(.spring(duration: 0.28)) { pulse = true }
    Task {
        try? await Task.sleep(for: .milliseconds(320))
        withAnimation(.easeOut(duration: 0.2)) { pulse = false }
    }
}
~~~

- [ ] **Step 3: Pass Reduce Motion và window active state từ screen**

Trong DevRoomWorkflowSummary, đọc Reduce Motion và animate riêng từng count:

~~~swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

Text("\(data.count(for: stage))")
    .font(.title.bold())
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(
        reduceMotion ? nil : .smooth(duration: 0.24),
        value: data.count(for: stage)
    )
~~~

Trong five-count strip của DevRoomEmployeeDesk, thay Text count bằng:

~~~swift
Text("\(summary.count(for: stage))")
    .monospacedDigit()
    .contentTransition(.numericText())
    .animation(
        reduceMotion ? nil : .smooth(duration: 0.24),
        value: summary.count(for: stage)
    )
~~~

Trong DevRoomView:

~~~swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
@Environment(\.controlActiveState) private var controlActiveState
~~~

Và khi tạo desk:

~~~swift
DevRoomEmployeeDesk(
    summary: employee,
    selectedStage: viewModel.selectedStage,
    animationEvent: viewModel.animationEvent,
    isWindowActive: controlActiveState == .key,
    reduceMotion: reduceMotion,
    onSelect: { viewModel.selectEmployee(employee.id) }
)
~~~

Với Reduce Motion, giữ dữ liệu cập nhật tức thời; chỉ bỏ idle loop và pulse/scale.

- [ ] **Step 4: Build và manual animation verify**

Run:

~~~bash
swift build
swift build -c release
swift run OpsHub
~~~

Expected:
- nhân vật gõ phím/chớp mắt lệch nhịp;
- chuyển menu hoặc window mất active thì idle animation dừng;
- bật Reduce Motion thì idle/pulse dừng;
- first load không pulse;
- refresh có added/stage/reassign/remove chỉ pulse employee bị ảnh hưởng;
- không animate lại toàn grid.

- [ ] **Step 5: Commit animation**

~~~bash
git add Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift
git commit -m "feat(dev-room): animate employee activity"
~~~

---

