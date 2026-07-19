### Task 7: Overlay detail drawer and selection rules

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
    let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [10, 20])
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
    let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [10])
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

- [ ] **Step 3: Sửa `toggleStage` để dùng selection validity từ Task 2**

```swift
func toggleStage(_ stage: DevRoomWorkflowStage) {
    selectedStage = selectedStage == stage ? nil : stage
    clearSelectionIfHidden()
}
```

Task 2 đã gọi `clearSelectionIfHidden()` sau refresh và allowlist update; Task 7 chỉ bổ sung call sau stage toggle.

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

