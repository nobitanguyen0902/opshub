### Task 5: Thêm top-level menu và lifecycle owner

**Files:**
- Modify: Sources/OpsHub/App/ContentView.swift:3-84
- Create: Tests/OpsHubTests/AppSectionTests.swift
- Create compile-safe shell, then complete in Task 6: Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift

**Interfaces:**
- Consumes: DevRoomViewModel(service:), GitLabService(settingsStore:).
- Produces: AppSection.devRoom route và ContentView-owned DevRoomViewModel.

- [ ] **Step 1: Viết failing AppSection order/title test**

Tạo Tests/OpsHubTests/AppSectionTests.swift:

~~~swift
import XCTest
@testable import OpsHub

final class AppSectionTests: XCTestCase {
    func testDevRoomAppearsAfterDashboardWithoutRemovingExistingSections() {
        XCTAssertEqual(
            AppSection.allCases,
            [.dashboard, .devRoom, .brew, .gitLab, .settings]
        )
        XCTAssertEqual(AppSection.devRoom.title, "Dev Room")
        XCTAssertEqual(AppSection.devRoom.systemImage, "person.3.fill")
    }
}
~~~

- [ ] **Step 2: Chạy test và xác nhận fail**

Run:

~~~bash
swift test --filter AppSectionTests
~~~

Expected: build FAIL vì AppSection.devRoom chưa tồn tại.

- [ ] **Step 3: Thêm AppSection, ViewModel owner và route**

Trong ContentView.swift:

~~~swift
enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case devRoom
    case brew
    case gitLab
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: "Dashboard"
        case .devRoom: "Dev Room"
        case .brew: "Brew"
        case .gitLab: "GitLab"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .devRoom: "person.3.fill"
        case .brew: "cup.and.saucer"
        case .gitLab: "arrow.triangle.branch"
        case .settings: "gearshape"
        }
    }
}
~~~

Thêm property và khởi tạo:

~~~swift
@StateObject private var devRoomViewModel: DevRoomViewModel
@StateObject private var gitLabViewModel: GitLabDashboardViewModel

let gitLabService = GitLabService(settingsStore: settingsStore)
_devRoomViewModel = StateObject(
    wrappedValue: DevRoomViewModel(service: gitLabService)
)
_gitLabViewModel = StateObject(
    wrappedValue: GitLabDashboardViewModel(service: gitLabService)
)
~~~

Thêm route:

~~~swift
case .devRoom:
    DevRoomView(viewModel: devRoomViewModel)
~~~

Tạo compile-safe shell trong DevRoomView.swift; Task 6 sẽ thay body:

~~~swift
import SwiftUI

struct DevRoomView: View {
    @ObservedObject var viewModel: DevRoomViewModel

    var body: some View {
        Text("Dev Room")
            .navigationTitle("Dev Room")
    }
}
~~~

- [ ] **Step 4: Chạy tests và build**

Run:

~~~bash
swift test --filter AppSectionTests
swift build
~~~

Expected: PASS và build succeeds. Mở ContentView preview không được xóa bất kỳ AppSection cũ nào.

- [ ] **Step 5: Commit navigation**

~~~bash
git add Sources/OpsHub/App/ContentView.swift Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift Tests/OpsHubTests/AppSectionTests.swift
git commit -m "feat(dev-room): add top-level navigation"
~~~

---

