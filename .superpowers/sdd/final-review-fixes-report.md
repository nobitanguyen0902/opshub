# Final review fixes report

## Kết quả

- Settings giữ riêng trạng thái catalog member đã tải thành công gần nhất. Trong lúc post-Save refresh đang chạy, `Clear`, `Select All` và draft vẫn có thể dùng trên catalog đó, và Save tiếp theo vẫn persist + apply allowlist thay vì bỏ qua vì transient `loading`.
- Trước lần tải member thành công đầu tiên, các thao tác đổi allowlist bị khóa ở cả UI và ViewModel. Nếu GitLab settings đã lưu nhưng member catalog chưa sẵn sàng, Save trả outcome riêng và UI hiển thị trạng thái GitLab-only thay vì báo toàn bộ settings đã lưu.
- Member refresh không tự chọn member mới; lỗi refresh vẫn giữ catalog/draft đã có; lỗi lưu GitLab vẫn không persist hoặc apply allowlist.
- Mọi đường đóng drawer do người dùng (`×`, scrim, `Esc`) đi qua `closeDetailDrawer()`. `DevRoomDrawerFocusRouter` đưa accessibility focus về workstation theo employee ID nếu element vẫn còn; mở/chuyển drawer tiếp tục để heading trong drawer tự nhận focus; cleanup không gửi focus tới workstation đã biến mất.
- Workstation được key rõ bằng employee ID và có transition opacity + scale `0.97` trong `0.18s`. Animation gắn trực tiếp vào transition của item, không tạo animation transaction trên `LazyVGrid`, nên sibling reflow tức thời; Reduce Motion dùng fade-only `0.12s`.
- Drawer animation cũng gắn trực tiếp vào transition của overlay thay vì `roomContent`; việc drawer đóng do employee bị remove không còn tạo ambient transaction trên `roomSurface` hoặc grid. Reduce Motion dùng drawer fade-only `0.12s`.
- Username profile mapping normalize case an toàn với `Dictionary(_:uniquingKeysWith:)`. Khi hai source key chỉ khác hoa/thường, original key nhỏ hơn theo lexicographic order thắng; regression dùng `ALICE` thắng `alice`.

## Files thay đổi cho final review

- `Sources/OpsHub/Shared/Components/SettingsView.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomMemberSelectionSection.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomDesignTokens.swift`
- `Sources/OpsHub/Features/DevRoom/Models/DevRoomChibiProfile.swift`
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomMemberSelectionViewModel.swift`
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift`
- `Tests/OpsHubTests/DevRoomMemberSelectionViewModelTests.swift`
- `Tests/OpsHubTests/GitLabSettingsStoreTests.swift`
- `Tests/OpsHubTests/DevRoomViewTests.swift`
- `Tests/OpsHubTests/DevRoomChibiProfileTests.swift`

## Regression evidence

- `testSuccessfulCatalogRemainsSaveableDuringRefresh`: catalog success không bị mất readiness trong transient refresh.
- `testDraftCannotChangeBeforeFirstSuccessfulCatalogLoad`: không thể tạo draft user-visible mà Save phải bỏ qua.
- `testSaveDuringMemberRefreshPersistsVisibleDraftAndReportsCompleteSuccess`: Save trong in-flight refresh persist/apply draft rỗng từ `Clear`, trả `.allSettingsSaved`, và member mới vẫn unselected.
- `testFailedMemberLoadDoesNotOverwriteSavedDevRoomAllowlist`: trả `.gitLabSettingsSavedOnly`, không báo success đầy đủ hoặc ghi đè allowlist.
- Focus-router tests kiểm tra mở/chuyển drawer không tranh focus với heading, close về workstation cũ và không focus element đã bị remove.
- Transition-policy tests kiểm tra fade+scale nhẹ, không movement, và Reduce Motion fade-only.
- Drawer-transition policy tests kiểm tra animation chỉ thuộc overlay, normal dùng slide+fade `0.24s` và Reduce Motion dùng fade-only `0.12s`.
- Username-collision test kiểm tra precedence deterministic sau case normalization.

## Verification

- `swift test --filter DevRoomMemberSelectionViewModelTests`: 7/7 pass.
- `swift test --filter GitLabSettingsStoreTests`: 12/12 pass.
- `swift test --filter DevRoomViewTests`: 16/16 pass.
- `swift test --filter DevRoomChibiProfileTests`: 7/7 pass.
- `swift test`: 149/149 pass.
- `swift build -c debug`: pass.
- `swift build -c release`: pass.
- `git diff --check`: pass.

Sandbox note: lần chạy lại focused Settings sau assertion cuối bị SwiftPM chặn ghi `/Users/nobitanguyen/.cache/clang/ModuleCache` với `Operation not permitted`; chạy lại đúng command ngoài sandbox đã được duyệt và 12/12 test pass. Không có source/test failure.

## Scope

- Không đổi GitLab endpoint, issue aggregation, allowlist persistence format, refresh interval hoặc dependency.
- Không stage hoặc commit.
- Giữ nguyên toàn bộ user scratch/worktree khác.

## Final read-only review

- Reviewer phát hiện grid-level animation transaction có thể làm sibling reflow và vẫn tạo layout motion khi Reduce Motion bật.
- Đã sửa bằng cách bỏ animation khỏi `LazyVGrid` và gắn animation trực tiếp vào transition của workstation keyed theo employee ID.
- Re-review cuối: không còn actionable findings; assessment `Ready — Yes`.
- Follow-up reviewer phát hiện drawer animation vẫn còn đặt trên parent `roomContent`, có thể tạo ambient grid reflow khi selection tự đóng.
- Đã bỏ parent animation hoàn toàn và chuyển animation vào `DevRoomDrawerTransitionPolicy.animatedTransition` của drawer overlay.
