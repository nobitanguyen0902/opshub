### Task 8: Integrate responsive office scene and overlay presentation

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
            DevRoomWorkflowSummary(
                data: viewModel.visibleData,
                selectedStage: viewModel.selectedStage,
                onSelect: viewModel.toggleStage
            )
            ZStack(alignment: .top) {
                DevRoomOfficeBackground()
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 24)],
                    spacing: 34
                ) {
                    ForEach(viewModel.displayedEmployees) { employee in
                        DevRoomWorkstation(
                            summary: employee,
                            animationEvent: displayedAnimationEvent,
                            isWindowActive: controlActiveState == .key,
                            reduceMotion: reduceMotion,
                            onSelect: { viewModel.selectEmployee(employee.id) }
                        )
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

Room empty state phải nằm trong ZStack office, trên background. Nếu `viewModel.hasConfiguredMembers == false`, message là `Chọn thành viên Dev Room trong Settings`; nếu đã cấu hình nhưng filter rỗng, dùng message hiện có theo selected stage.

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

