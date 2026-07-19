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
