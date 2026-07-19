# Dev Room Visual Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Thêm allowlist Project members trong Settings và thay giao diện Dev Room dạng card rời bằng một căn phòng chung có nhiều Flat Chibi đang làm việc, employee tag tối giản và detail drawer trượt từ phải.

**Architecture:** `GitLabService` thêm Project Members API qua protocol riêng; allowlist ID được lưu bằng store riêng và áp dụng trong `DevRoomViewModel` trên full issue cache. Tách presentation thành profile store thuần dữ liệu, Flat Chibi nhiều layer, workstation, office background và overlay drawer; `DevRoomView` chỉ phối hợp state và layout. Những behavior có thể kiểm thử không cần render được đưa vào service/store/model/ViewModel và viết test trước.

**Tech Stack:** Swift 6, SwiftUI, macOS 14, XCTest, SF Symbols; không thêm package, asset raster, Lottie hoặc Rive.

## Global Constraints

- Project tiếp tục là `social/socom-issues`; chỉ đọc GitLab issue `opened` có assignee và workflow label hợp lệ.
- Giữ nguyên thứ tự `Todo → Doing → ToTest → Test → Passed`, pagination, dedupe issue ID, refresh thủ công và auto-refresh hai phút.
- Không thay đổi Dashboard, Brew, GitLab hoặc top-level navigation.
- Settings chỉ bổ sung section `Dev Room Members`; GitLab connection behavior hiện có phải giữ nguyên.
- Danh sách cấu hình lấy đủ `/projects/:id/members/all`, `per_page=100`, pagination theo `X-Next-Page`.
- Allowlist mặc định rỗng, lưu bằng GitLab user ID; member mới không tự được chọn.
- Checkbox chỉ sửa draft; Save chung lưu GitLab settings trước rồi mới lưu allowlist và áp dụng lên Dev Room.
- Task của user không được chọn không xuất hiện và không được tính vào workflow summary.
- Không sửa label, assignee hoặc state GitLab từ Dev Room.
- Room là một office scene chung; không dùng card/container lớn bao quanh từng nhân viên.
- Employee tag chỉ hiển thị avatar, display name, tổng task và stage dot.
- Flat Chibi được dựng bằng SwiftUI layers; profile thủ công có fallback ổn định theo employee ID.
- Drawer rộng khoảng `360pt`, overlay lên Room và không làm workstation grid reflow.
- Reduce Motion và inactive window phải dừng idle/pulse; drawer bỏ animation khi Reduce Motion bật.
- Bảo toàn thay đổi local không liên quan, đặc biệt `.swiftpm/xcode/package.xcworkspace/xcuserdata/nobitanguyen.xcuserdatad/UserInterfaceState.xcuserstate` và `.superpowers/brainstorm/`.

---

## File Structure

### Files tạo mới

- `Sources/OpsHub/Features/DevRoom/Models/DevRoomMember.swift` — Project member model và access-level presentation.
- `Sources/OpsHub/Features/DevRoom/Services/DevRoomMemberServices.swift` — protocol tải toàn bộ Project members.
- `Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift` — persisted selected GitLab user IDs.
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomMemberSelectionViewModel.swift` — members loading, search và draft selection.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomMemberSelectionSection.swift` — Settings UI chọn thành viên.
- `Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift` — token profile, curated mapping và deterministic fallback.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomOfficeBackground.swift` — tường, sàn, cửa sổ, đồng hồ và cây bằng SwiftUI shape.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeTag.swift` — employee tag tối giản.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkstation.swift` — ghép tag, Flat Chibi, laptop và bàn.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailDrawer.swift` — sidebar overlay và grouped issue detail.
- `Tests/OpsHubTests/DevRoomVisibilitySettingsStoreTests.swift` — default-empty và persistence tests.
- `Tests/OpsHubTests/DevRoomMemberSelectionViewModelTests.swift` — load/search/draft/save-state tests.
- `Tests/OpsHubTests/DevRoomChibiProfileTests.swift` — curated/fallback profile tests.

### Files sửa

- `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift` — thay hình học hiện tại bằng Flat Chibi nhiều layer.
- `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift` — Project Members endpoint và pagination.
- `Sources/OpsHub/Shared/Components/SettingsView.swift` — member section và Save chung.
- `Sources/OpsHub/App/ContentView.swift` — inject visibility store/member service và apply callback.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift` — office palette, room sizing và drawer width.
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift` — thu gọn summary strip.
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift` — stage representative và đóng selection khi filter loại nhân viên.
- `Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift` — visible-data projection và representative stage.
- `Tests/OpsHubTests/DevRoomServiceTests.swift` — Project Members request mapping/pagination.
- `Tests/OpsHubTests/GitLabSettingsStoreTests.swift` — Save GitLab failure remains isolated from allowlist callback.
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift` — office scene, responsive grid và overlay drawer.
- `Tests/OpsHubTests/DevRoomViewModelTests.swift` — selection/filter behavior và representative stage.

### Files xóa sau khi thay thế hoàn toàn

- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift`

---

### Task 1: Project member API and pagination

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/Models/DevRoomMember.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Services/DevRoomMemberServices.swift`
- Modify: `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`
- Modify: `Tests/OpsHubTests/DevRoomServiceTests.swift`

**Interfaces:**
- Consumes: `GitLabWorkflowProject.path`, `GitLabService.makeRequest(settings:path:queryItems:)`, `sendAllPages(_:)`.
- Produces: `DevRoomMemberServicing.projectMembers(projectPath:) async throws -> [DevRoomProjectMember]` cho Settings Task 3.

- [ ] **Step 1: Viết failing test cho members/all và pagination**

Thêm vào `DevRoomServiceTests`:

```swift
func testProjectMembersLoadsAllPagesAndMapsIdentity() async throws {
    let httpClient = DevRoomStubGitLabHTTPClient(responses: [
        "/api/v4/projects/social%2Fsocom-issues/members/all": DevRoomStubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":19,"username":"alice","name":"Alice","avatar_url":"https://gitlab.example.com/alice.png","access_level":30}]"#,
            headers: ["X-Next-Page": "2"]
        ),
        "/api/v4/projects/social%2Fsocom-issues/members/all?page=2": DevRoomStubHTTPResponse(
            statusCode: 200,
            body: #"[{"id":20,"username":"bob","name":"Bob","avatar_url":null,"access_level":40}]"#
        )
    ])
    let service = GitLabService(
        settingsStore: DevRoomStaticGitLabSettingsStore(),
        httpClient: httpClient
    )

    let members = try await service.projectMembers(projectPath: GitLabWorkflowProject.path)

    XCTAssertEqual(members.map(\.id), [19, 20])
    XCTAssertEqual(members.map(\.username), ["alice", "bob"])
    XCTAssertEqual(members.map(\.accessLevel), [30, 40])
    XCTAssertEqual(httpClient.requests.count, 2)
    let first = try XCTUnwrap(httpClient.requests.first?.url)
    let components = try XCTUnwrap(URLComponents(url: first, resolvingAgainstBaseURL: false))
    XCTAssertEqual(components.percentEncodedPath, "/api/v4/projects/social%2Fsocom-issues/members/all")
    XCTAssertTrue(components.queryItems?.contains(URLQueryItem(name: "per_page", value: "100")) == true)
}
```

- [ ] **Step 2: Chạy test để xác nhận fail vì method chưa tồn tại**

```bash
swift test --filter DevRoomServiceTests/testProjectMembers
```

Expected: build fail với `value of type 'GitLabService' has no member 'projectMembers'`.

- [ ] **Step 3: Tạo member model và service protocol riêng**

```swift
import Foundation

struct DevRoomProjectMember: Identifiable, Equatable, Hashable, Sendable {
    let id: Int
    let username: String
    let name: String
    let avatarURL: URL?
    let accessLevel: Int

    var accessLevelTitle: String {
        switch accessLevel {
        case 50...: "Owner"
        case 40..<50: "Maintainer"
        case 30..<40: "Developer"
        case 20..<30: "Reporter"
        case 10..<20: "Guest"
        default: "Minimal access"
        }
    }
}
```

```swift
protocol DevRoomMemberServicing: Sendable {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember]
}
```

- [ ] **Step 4: Implement DTO, request builder và mapping trong GitLabService**

DTO private dùng snake-case decode hiện có:

```swift
private struct GitLabProjectMember: Decodable {
    let id: Int
    let username: String
    let name: String
    let avatarUrl: URL?
    let accessLevel: Int

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarUrl = "avatar_url"
        case accessLevel = "access_level"
    }
}
```

Thêm helper tổng quát cho project subpath để issues và members cùng encode `/` thành `%2F`:

```swift
private func makeProjectRequest(
    settings: GitLabSettings,
    projectPath: String,
    suffix: String,
    queryItems: [URLQueryItem]
) throws -> URLRequest
```

`projectMembers` dùng suffix `members/all`, query `per_page=100`, `sendAllPages`, map model và sort theo `name.localizedCaseInsensitiveCompare`, tie-break theo ID.

- [ ] **Step 5: Chạy tests service liên quan**

```bash
swift test --filter DevRoomServiceTests
swift test --filter GitLabServiceTests
```

Expected: toàn bộ pass; request issue hiện có vẫn giữ nguyên path/query.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/Models/DevRoomMember.swift Sources/OpsHub/Features/DevRoom/Services/DevRoomMemberServices.swift Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift Tests/OpsHubTests/DevRoomServiceTests.swift
git commit -m "feat(dev-room): load project members"
```

---

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

### Task 3: Settings member selection and Save integration

**Files:**
- Create: `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomMemberSelectionViewModel.swift`
- Create: `Sources/OpsHub/Features/DevRoom/Components/DevRoomMemberSelectionSection.swift`
- Create: `Tests/OpsHubTests/DevRoomMemberSelectionViewModelTests.swift`
- Modify: `Sources/OpsHub/Shared/Components/SettingsView.swift`
- Modify: `Sources/OpsHub/App/ContentView.swift`
- Modify: `Tests/OpsHubTests/AppSectionTests.swift`

**Interfaces:**
- Consumes: `DevRoomMemberServicing`, `DevRoomVisibilitySettingsStoring`, `DevRoomViewModel.applySelectedUserIDs(_:)`.
- Produces: Settings draft selection, member loading/search/retry và Save callback cập nhật cached Dev Room.

- [ ] **Step 1: Viết failing ViewModel tests cho load/search/draft**

```swift
@MainActor
func testLoadKeepsSavedSelectionAndFiltersByNameOrUsername() async {
    let service = StubDevRoomMemberService(members: [
        member(id: 10, username: "alice", name: "Alice Nguyen"),
        member(id: 20, username: "bob", name: "Bob Tran")
    ])
    let viewModel = DevRoomMemberSelectionViewModel(
        service: service,
        initialSelectedUserIDs: [20]
    )

    await viewModel.loadMembers()
    viewModel.searchText = "alice"

    XCTAssertEqual(viewModel.filteredMembers.map(\.id), [10])
    XCTAssertEqual(viewModel.draftSelectedUserIDs, [20])
    XCTAssertTrue(viewModel.hasLoadedMembers)
}

@MainActor
func testFailedLoadDoesNotReplaceSavedDraftWithEmptySelection() async {
    let viewModel = DevRoomMemberSelectionViewModel(
        service: FailingDevRoomMemberService(),
        initialSelectedUserIDs: [20]
    )

    await viewModel.loadMembers()

    XCTAssertEqual(viewModel.draftSelectedUserIDs, [20])
    XCTAssertFalse(viewModel.hasLoadedMembers)
    guard case .failed = viewModel.loadState else {
        return XCTFail("Expected failed member load")
    }
}
```

- [ ] **Step 2: Implement member-selection ViewModel**

```swift
enum DevRoomMemberLoadState: Equatable {
    case idle, loading, loaded, empty, failed(String)
}

@MainActor
final class DevRoomMemberSelectionViewModel: ObservableObject {
    @Published private(set) var members: [DevRoomProjectMember] = []
    @Published private(set) var loadState: DevRoomMemberLoadState = .idle
    @Published var searchText = ""
    @Published private(set) var draftSelectedUserIDs: Set<Int>

    private let service: any DevRoomMemberServicing
    var hasLoadedMembers: Bool { loadState == .loaded || loadState == .empty }
    var filteredMembers: [DevRoomProjectMember] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else { return members }
        return members.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    init(service: any DevRoomMemberServicing, initialSelectedUserIDs: Set<Int>) {
        self.service = service
        draftSelectedUserIDs = initialSelectedUserIDs
    }

    func loadMembers() async {
        guard loadState != .loading else { return }
        let previousState = loadState
        loadState = .loading
        do {
            let loaded = try await service.projectMembers(projectPath: GitLabWorkflowProject.path)
            guard Task.isCancelled == false else {
                loadState = previousState
                return
            }
            members = loaded
            loadState = loaded.isEmpty ? .empty : .loaded
        } catch where Task.isCancelled {
            loadState = previousState
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggle(_ id: Int) {
        if draftSelectedUserIDs.contains(id) {
            draftSelectedUserIDs.remove(id)
        } else {
            draftSelectedUserIDs.insert(id)
        }
    }
    func selectAll() { draftSelectedUserIDs.formUnion(members.map(\.id)) }
    func clear() { draftSelectedUserIDs.removeAll() }
    func markSaved(_ ids: Set<Int>) { draftSelectedUserIDs = ids }
}
```

Implement code đầy đủ, không để comment marker trong source; catch cancellation riêng và restore state trước request.

- [ ] **Step 3: Tạo `DevRoomMemberSelectionSection`**

Section nhận `@ObservedObject var viewModel` và render:

- heading + fixed project path + selected count;
- SearchField/TextField;
- `Select All`, `Clear`;
- ProgressView, failed + Retry, empty state;
- LazyVStack member rows có checkbox, AsyncImage, name, username, ID, access-level title.

Checkbox gọi `viewModel.toggle(member.id)` và không truy cập store. Selected accessibility value là `Đã chọn`/`Chưa chọn`.

- [ ] **Step 4: Tích hợp Save chung theo thứ tự an toàn**

`SettingsView` init thêm:

```swift
visibilityStore: any DevRoomVisibilitySettingsStoring = DevRoomVisibilitySettingsStore(),
memberService: any DevRoomMemberServicing = GitLabService(),
onDevRoomVisibilitySaved: @escaping (Set<Int>) -> Void = { _ in }
```

Các default giữ `#Preview` và call site độc lập compile. `ContentView` phải inject shared instances thật. Khởi tạo `@StateObject memberSelectionViewModel` bằng selection đã lưu. `saveSettings()` thực hiện:

```swift
try settingsStore.save(gitLabSettings)
if memberSelectionViewModel.hasLoadedMembers {
    let ids = memberSelectionViewModel.draftSelectedUserIDs
    visibilityStore.save(DevRoomVisibilitySettings(selectedUserIDs: ids))
    onDevRoomVisibilitySaved(ids)
    memberSelectionViewModel.markSaved(ids)
}
```

Nếu `settingsStore.save` throw, đoạn visibility không chạy. Sau Save GitLab thành công, gọi `Task { await memberSelectionViewModel.loadMembers() }` để connection mới refresh member catalog.

- [ ] **Step 5: Inject shared store/service from ContentView**

Trong `ContentView.init` tạo một `DevRoomVisibilitySettingsStore`, load IDs, dùng cùng `GitLabService` cho issues/members, và khởi tạo ViewModel:

```swift
let visibilityStore = DevRoomVisibilitySettingsStore()
let selectedUserIDs = visibilityStore.load().selectedUserIDs
let gitLabService = GitLabService(settingsStore: settingsStore)
_devRoomViewModel = StateObject(
    wrappedValue: DevRoomViewModel(
        service: gitLabService,
        selectedUserIDs: selectedUserIDs
    )
)
```

Giữ store/service thành properties để truyền vào Settings. Callback dùng `devRoomViewModel.applySelectedUserIDs`.

- [ ] **Step 6: Chạy Settings/member/navigation tests và builds**

```bash
swift test --filter DevRoomMemberSelectionViewModelTests
swift test --filter DevRoomVisibilitySettingsStoreTests
swift test --filter AppSectionTests
swift test --filter GitLabSettingsStoreTests
swift build
swift build -c release
```

Expected: pass; menu order không đổi và Settings connection tests không regression.

- [ ] **Step 7: Commit**

```bash
git add Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomMemberSelectionViewModel.swift Sources/OpsHub/Features/DevRoom/Components/DevRoomMemberSelectionSection.swift Sources/OpsHub/Shared/Components/SettingsView.swift Sources/OpsHub/App/ContentView.swift Tests/OpsHubTests/DevRoomMemberSelectionViewModelTests.swift Tests/OpsHubTests/AppSectionTests.swift
git commit -m "feat(dev-room): configure visible project members"
```

---

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

### Task 9: Visual acceptance, accessibility and regression hardening

**Files:**
- Modify only if acceptance finds a confirmed issue in `Sources/OpsHub/Features/DevRoom/**`, `Sources/OpsHub/Shared/Components/SettingsView.swift`, `Sources/OpsHub/App/ContentView.swift` hoặc covering tests.

**Interfaces:**
- Consumes: hoàn chỉnh member allowlist và Dev Room visual redesign từ Tasks 1–8.
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

```bash
rg "DevRoomMemberSelectionSection|DevRoomVisibilitySettingsStore|projectMembers" Sources/OpsHub
```

Expected: Settings, ContentView và GitLabService đều nối vào allowlist flow.

- [ ] **Step 2: Chạy focused regression families**

```bash
swift test --filter DevRoom
swift test --filter DevRoomVisibilitySettingsStoreTests
swift test --filter DevRoomMemberSelectionViewModelTests
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

1. Settings tải đủ Project members, search theo name/username và hiển thị avatar, ID, access level.
2. Member mới mặc định chưa chọn; checkbox, Select All, Clear chỉ thay draft trước Save.
3. Save chung áp dụng allowlist; mở lại app vẫn giữ đúng selected IDs.
4. User bị bỏ chọn biến mất và task của họ không còn trong workflow counts; allowlist rỗng hướng dẫn vào Settings.
5. Room trông như một office scene chung, không còn card lớn quanh từng employee.
6. Mỗi workstation chỉ có avatar, name, total task và stage dot.
7. Flat Chibi hiện khác tóc/da/áo/phụ kiện theo profile; employee chưa map vẫn có profile ổn định theo ID.
8. Chibi gõ phím/chớp mắt lệch nhịp; window inactive và Reduce Motion dừng animation.
9. Click tag/chibi/laptop/desk đều mở đúng employee drawer.
10. Drawer slide từ phải và overlay lên Room; grid không reflow.
11. Nút xmark, click scrim và Escape đều đóng drawer.
12. Click issue mở GitLab bằng browser mặc định.
13. Workflow filter vẫn đúng; selection bị loại khỏi filter hoặc allowlist thì drawer đóng.
14. Refresh và task-change pulse chỉ tác động employee phù hợp.

Không để process GUI chạy nền sau acceptance.

- [ ] **Step 5: Fix confirmed acceptance issues minimally and rerun covering gates**

Mỗi fix phải có regression test ở model/ViewModel nếu behavior có seam testable. Không thêm snapshot-test dependency hoặc refactor ngoài Dev Room.

- [ ] **Step 6: Final diff review and commit if Task 9 changed code**

```bash
git diff --stat 88b9226..HEAD
git diff 88b9226..HEAD -- Sources/OpsHub/Features/DevRoom Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift Sources/OpsHub/Shared/Components/SettingsView.swift Sources/OpsHub/App/ContentView.swift Tests/OpsHubTests
```

Nếu có fix ở Task 9:

```bash
git add Sources/OpsHub/Features/DevRoom Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift Sources/OpsHub/Shared/Components/SettingsView.swift Sources/OpsHub/App/ContentView.swift Tests/OpsHubTests
git commit -m "fix(dev-room): finalize shared office presentation"
```

Không stage `.swiftpm/xcode/package.xcworkspace/xcuserdata/nobitanguyen.xcuserdatad/UserInterfaceState.xcuserstate` hoặc `.superpowers/brainstorm/`.

---

## Final Review Gate

Sau Task 9:

1. Dùng `superpowers:requesting-code-review` để review range `88b9226..HEAD`.
2. Reviewer phải kiểm tra spec `docs/superpowers/specs/2026-07-19-dev-room-visual-redesign-design.md`, member API pagination, default-empty allowlist, Save ordering, visibility counts, cancellation/lifecycle animation, accessibility, responsive room và không regression GitLab.
3. Fix toàn bộ Critical/Important findings bằng một task riêng, chạy lại targeted/full gates và re-review.
4. Không push hoặc tạo PR nếu user chưa yêu cầu.
