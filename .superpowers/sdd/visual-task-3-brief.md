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

