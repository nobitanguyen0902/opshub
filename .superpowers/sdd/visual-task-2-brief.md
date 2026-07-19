### Task 2: Persisted allowlist and visible Dev Room projection

**Files:**
- Create: `Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift`
- Create: `Tests/OpsHubTests/DevRoomVisibilitySettingsStoreTests.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift`
- Modify: `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift`
- Modify: `Tests/OpsHubTests/DevRoomViewModelTests.swift`

**Interfaces:**
- Consumes: full `DevRoomData` cache và GitLab employee IDs.
- Produces: `DevRoomVisibilitySettingsStore`, `DevRoomViewModel.applySelectedUserIDs(_:)`, `visibleData`, `hasConfiguredMembers` cho UI Tasks 3 và 8.

- [ ] **Step 1: Viết failing tests cho default-empty và persistence**

```swift
import XCTest
@testable import OpsHub

final class DevRoomVisibilitySettingsStoreTests: XCTestCase {
    func testNewStoreDefaultsToEmptyAllowlist() throws {
        let suite = "DevRoomVisibilitySettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = DevRoomVisibilitySettingsStore(userDefaults: defaults)

        XCTAssertEqual(store.load().selectedUserIDs, [])
    }

    func testSavePersistsSortedUniqueUserIDs() throws {
        let suite = "DevRoomVisibilitySettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DevRoomVisibilitySettingsStore(userDefaults: defaults)

        store.save(DevRoomVisibilitySettings(selectedUserIDs: [20, 10]))

        XCTAssertEqual(store.load().selectedUserIDs, [10, 20])
        XCTAssertEqual(defaults.array(forKey: "devRoom.selectedUserIDs") as? [Int], [10, 20])
    }
}
```

- [ ] **Step 2: Implement visibility settings store**

```swift
import Foundation

struct DevRoomVisibilitySettings: Equatable, Sendable {
    let selectedUserIDs: Set<Int>
}

protocol DevRoomVisibilitySettingsStoring {
    func load() -> DevRoomVisibilitySettings
    func save(_ settings: DevRoomVisibilitySettings)
}

final class DevRoomVisibilitySettingsStore: DevRoomVisibilitySettingsStoring {
    private let userDefaults: UserDefaults
    private let selectedUserIDsKey: String

    init(
        userDefaults: UserDefaults = .standard,
        selectedUserIDsKey: String = "devRoom.selectedUserIDs"
    ) {
        self.userDefaults = userDefaults
        self.selectedUserIDsKey = selectedUserIDsKey
    }

    func load() -> DevRoomVisibilitySettings {
        let ids = userDefaults.array(forKey: selectedUserIDsKey) as? [Int] ?? []
        return DevRoomVisibilitySettings(selectedUserIDs: Set(ids))
    }

    func save(_ settings: DevRoomVisibilitySettings) {
        userDefaults.set(settings.selectedUserIDs.sorted(), forKey: selectedUserIDsKey)
    }
}
```

- [ ] **Step 3: Viết failing ViewModel tests cho visible projection**

```swift
@MainActor
func testAllowlistFiltersEmployeesIssuesAndWorkflowCounts() async {
    let service = SequencedDevRoomService(results: [[
        source(id: 1, employeeID: 10, labels: ["Todo"]),
        source(id: 2, employeeID: 20, labels: ["Passed"])
    ]])
    let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [20])

    await viewModel.refresh()

    XCTAssertEqual(viewModel.data.total, 2)
    XCTAssertEqual(viewModel.visibleData.total, 1)
    XCTAssertEqual(viewModel.visibleData.employees.map(\.employee.id), [20])
    XCTAssertEqual(viewModel.visibleData.count(for: .todo), 0)
    XCTAssertEqual(viewModel.visibleData.count(for: .passed), 1)
}

@MainActor
func testApplyingEmptyAllowlistClosesDrawerAndShowsNoEmployees() async {
    let service = SequencedDevRoomService(results: [[
        source(id: 1, employeeID: 10, labels: ["Doing"])
    ]])
    let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [10])
    await viewModel.refresh()
    viewModel.selectEmployee(10)

    viewModel.applySelectedUserIDs([])

    XCTAssertTrue(viewModel.visibleData.employees.isEmpty)
    XCTAssertNil(viewModel.selectedEmployeeID)
}
```

- [ ] **Step 4: Implement `DevRoomData.filtered(userIDs:)`**

```swift
extension DevRoomData {
    func filtered(userIDs: Set<Int>) -> DevRoomData {
        let visibleIssues = issues.filter { userIDs.contains($0.assignee.id) }
        let visibleEmployees = employees.filter { userIDs.contains($0.employee.id) }
        return DevRoomData(issues: visibleIssues, employees: visibleEmployees)
    }
}
```

- [ ] **Step 5: Add allowlist state without changing full snapshot/cache**

```swift
@Published private(set) var selectedUserIDs: Set<Int>

init(service: any DevRoomServicing, selectedUserIDs: Set<Int> = []) {
    self.service = service
    self.selectedUserIDs = selectedUserIDs
}

var visibleData: DevRoomData { data.filtered(userIDs: selectedUserIDs) }
var hasConfiguredMembers: Bool { selectedUserIDs.isEmpty == false }

func applySelectedUserIDs(_ ids: Set<Int>) {
    selectedUserIDs = ids
    clearSelectionIfHidden()
}

private func clearSelectionIfHidden() {
    guard let selectedEmployeeID else { return }
    if displayedEmployees.contains(where: { $0.id == selectedEmployeeID }) == false {
        self.selectedEmployeeID = nil
    }
}
```

`displayedEmployees` và `selectedEmployee` đọc từ `visibleData`. Sau refresh thành công gọi `clearSelectionIfHidden()` thay check trên full `data`. Snapshot diff tiếp tục tạo từ full `newData` để bật lại user không cần refetch và không làm sai baseline.

Cập nhật các test cũ có assertion về `displayedEmployees`/selection để truyền allowlist rõ ràng:

```swift
let viewModel = DevRoomViewModel(
    service: service,
    selectedUserIDs: [10, 20]
)
```

Không đổi các test chỉ xác nhận full cache `data`, refresh, cancellation hoặc snapshot.

- [ ] **Step 6: Chạy store/ViewModel tests**

```bash
swift test --filter DevRoomVisibilitySettingsStoreTests
swift test --filter DevRoomViewModelTests
```

Expected: pass; full `data` vẫn có hai issues trong test projection, visible data chỉ có allowlist.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift Tests/OpsHubTests/DevRoomVisibilitySettingsStoreTests.swift Tests/OpsHubTests/DevRoomViewModelTests.swift
git commit -m "feat(dev-room): persist visible member allowlist"
```

---

