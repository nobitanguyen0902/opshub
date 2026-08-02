# Terminal Tab Rename Implementation Plan

> **For Hermes:** Implement this plan task-by-task; do not commit unless the user explicitly requests it.

**Goal:** Cho phép đổi tên thủ công từng tab Terminal qua menu chuột phải, trong khi tab mới tiếp tục được tự động đặt tên `Terminal N`.

**Architecture:** Mở rộng model session hiện có để title trở thành observable mutable state, đặt nghiệp vụ đổi tên trong `CodexTerminalViewModel`, và chỉ giữ trạng thái nhập/hiển thị dialog tại `CodexTerminalView`. Không thay đổi host SwiftTerm, process shell, start directory hoặc vòng đời session.

**Tech Stack:** Swift 6, SwiftUI, AppKit/SwiftTerm, XCTest, macOS 14+.

---

## 1. Solution Summary

Giữ nguyên cơ chế auto-name hiện tại (`Terminal 1`, `Terminal 2`, ...). Trên mỗi tab, bổ sung context menu với action `Rename Tab`. Action mở dialog chứa tên hiện tại; khi xác nhận, view gọi ViewModel để cập nhật title của đúng session. Manual title chỉ tồn tại trong vòng đời session hiện tại, phù hợp với contract hiện có là terminal session không được restore sau khi restart app.

Không cần thay đổi `SwiftTermCodexTerminalHost`: yêu cầu đang nói tới tab do OpsHub render trong `CodexTerminalView`, không phải tab của ứng dụng Apple Terminal.app hay title do escape sequence bên trong shell phát ra.

## 2. Requirement Understanding

### Mục tiêu

- Tab mới tự động có tên `Terminal N`.
- Người dùng nhấp chuột phải lên tab và chọn đổi tên.
- Tên mới hiển thị ngay sau khi xác nhận.
- Rename không tác động process, output, selection hoặc session khác.

### Phạm vi

- Feature Terminal nhúng trong OpsHub trên macOS.
- Chỉ title của tab trong UI OpsHub.
- Không đổi shell command, working directory, SwiftTerm host hoặc lifecycle.

### Business rules đã chốt

1. Auto-name dùng chính xác mẫu hiện có `Terminal N` với bộ đếm tăng dần trong vòng đời ViewModel.
2. Rename được mở từ context menu của tab.
3. Manual rename ghi đè title hiện tại của session đó.
4. Auto-name chỉ chạy khi tạo session, nên không thể ghi đè manual title về sau.

### Giả định kỹ thuật cần xác nhận khi review UI

- Không persistence sau khi restart app; README hiện xác nhận session/tab không được restore.
- Cho phép trùng tên vì title là nhãn hiển thị, session được định danh bằng UUID.
- Trim whitespace đầu/cuối; không chấp nhận tên rỗng sau trim. Dialog giữ mở hoặc nút xác nhận bị disable khi input không hợp lệ.
- Không đặt giới hạn độ dài nghiệp vụ; UI tab tiếp tục xử lý bằng layout/scroll hiện có. Có thể thêm truncation UI nếu kiểm tra thực tế cho thấy tên dài phá layout, nhưng không tự cắt dữ liệu.
- Chuỗi UI theo convention hiện tại là tiếng Anh: `Rename Tab`, `Tab Name`, `Rename`, `Cancel`.

## 3. Technical Design

### Kiến trúc và ownership

- `CodexTerminalSession` sở hữu title runtime của từng session.
- `CodexTerminalViewModel` sở hữu mutation API và validation/normalization để View không sửa model trực tiếp.
- `CodexTerminalView` sở hữu transient presentation state: session đang rename, draft title, dialog visibility.
- `CodexTerminalSessionFactory` tiếp tục nhận initial title và không thay đổi contract.
- `SwiftTermCodexTerminalHost` không tham gia rename.

### Luồng tạo mới

1. Người dùng chọn `New Terminal`.
2. `CodexTerminalViewModel.createSession()` tạo title `Terminal N` như hiện tại.
3. Factory tạo session/host; session được append và select.
4. Counter tăng, không phụ thuộc manual rename hoặc việc đóng tab.

Ví dụ: đổi `Terminal 1` thành `Architect`, sau đó tạo tab mới vẫn là `Terminal 2`.

### Luồng rename

1. Người dùng nhấp chuột phải vào vùng tab cần đổi tên.
2. Context menu hiển thị `Rename Tab`.
3. View lưu session ID và prefill draft bằng title hiện tại, rồi mở rename dialog.
4. Người dùng sửa tên và xác nhận.
5. ViewModel tìm session theo UUID, normalize tên, cập nhật title nếu hợp lệ.
6. Vì title là observable, label tab, accessibility label và close-button accessibility label cập nhật ngay.
7. Không select tab ngầm và không restart/interrupt host.

### Thành phần thay đổi

- `Sources/OpsHub/Features/CodexTerminal/Models/CodexTerminalModels.swift`
  - Chuyển `title` từ immutable sang published mutable state có kiểm soát.
  - Session vẫn giữ UUID và host như hiện tại.

- `Sources/OpsHub/Features/CodexTerminal/ViewModels/CodexTerminalViewModel.swift`
  - Thêm API rename theo session ID.
  - Normalize whitespace và từ chối input rỗng.
  - Không thay đổi create/select/close/terminate flow.

- `Sources/OpsHub/Features/CodexTerminal/Views/CodexTerminalView.swift`
  - Gắn context menu vào toàn bộ container tab, không chỉ text label.
  - Thêm rename dialog với text field được prefill.
  - Disable xác nhận với tên không hợp lệ.
  - Reset presentation state khi cancel/submit; xử lý an toàn nếu session đã đóng trước lúc submit.

- `Tests/OpsHubTests/CodexTerminalViewModelTests.swift`
  - Regression tests cho auto-name và manual rename.

- `README.md`
  - Cập nhật mô tả ngắn về auto-name và context-menu rename; nhắc title/session không restore.

### Không thay đổi

- `CodexTerminalSessionCreating` và factory signature.
- `CodexTerminalHostView.swift` và SwiftTerm delegate `setTerminalTitle`.
- Database, cache, API, event, config, permission, infrastructure, packaging.

## 4. Impact Analysis

### Module

Chỉ ảnh hưởng feature `CodexTerminal`, test tương ứng và tài liệu Terminal.

### API/contract nội bộ

`CodexTerminalSession.title` đổi từ immutable sang observable mutable property. Đây là internal source-level change trong executable target, không phải public API. Nên giới hạn setter nếu Swift cho phép phù hợp với cách ViewModel mutation để tránh View sửa trực tiếp.

### UI/accessibility

- Context menu mới trên tab.
- Rename dialog mới.
- Existing `Text(session.title)`, tab accessibility label và close accessibility label phải phản ánh title mới.
- Tab strip horizontal scroll vẫn giữ nguyên.

### Data/persistence

Không có database/schema/migration. Rename là in-memory và mất khi đóng session hoặc restart app.

### Process/concurrency

Tất cả model/ViewModel/UI đang `@MainActor`; rename đồng bộ trên main actor. Không gửi input vào PTY và không tương tác child process.

### Dependencies/infrastructure

Không thêm dependency, entitlement, config, CI/CD hoặc packaging change.

### Test

Mở rộng unit tests ViewModel; UI context menu/dialog cần smoke-test thủ công vì project chưa có UI-test target.

## 5. Risk Analysis

### Title đổi nhưng UI không refresh — Trung bình

**Nguyên nhân:** `CodexTerminalSession` là nested `ObservableObject`; parent ViewModel publishing array không tự phát event khi property bên trong đổi. `ForEach` hiện không có child observer riêng.

**Giảm thiểu:** tab item phải observe từng session (ví dụ tách thành child View nhận `@ObservedObject`) hoặc ViewModel phải phát change một cách rõ ràng. Ưu tiên child View vì đúng ownership SwiftUI và tránh phát event thủ công.

### Context menu chỉ hoạt động trên vùng nhỏ — Thấp

**Nguyên nhân:** modifier đặt trên `Text`/Button thay vì tab container.

**Giảm thiểu:** đặt `.contextMenu` trên toàn bộ HStack/container của tab và xác minh click phải ở padding/background.

### Rename nhầm session khi nhiều tab — Trung bình

**Nguyên nhân:** dùng selected session thay vì UUID của tab được click phải.

**Giảm thiểu:** context menu capture đúng `session.id`; dialog state giữ target ID độc lập với `selectedSessionID`; unit test rename non-selected tab.

### Session bị đóng khi dialog đang mở — Thấp

**Nguyên nhân:** target UUID không còn trong collection khi submit.

**Giảm thiểu:** ViewModel rename là no-op/return failure khi không tìm thấy; View dọn state. Không crash, không rename tab khác.

### Input rỗng hoặc chỉ whitespace — Thấp

**Giảm thiểu:** dùng chung normalization/validation trong ViewModel; UI disable `Rename` nhưng ViewModel vẫn tự bảo vệ contract.

### Tên rất dài làm giảm usability — Thấp

**Giảm thiểu:** giữ horizontal scroll hiện tại; smoke-test tên dài. Chỉ thêm truncation/tooltip nếu cần, không giới hạn dữ liệu khi requirement chưa yêu cầu.

### Xung đột với escape-sequence title của terminal — Thấp

SwiftTerm delegate `setTerminalTitle` hiện bỏ qua title từ process. Không nối delegate này vào session title, nhờ đó manual title không bị shell command ghi đè.

### Backward compatibility/deployment/rollback — Thấp

Không migration và không thay process contract. Rollback chỉ cần hoàn nguyên model/ViewModel/View/test/docs liên quan.

## 6. Decision Log

### D1 — Giữ auto-name `Terminal N` hiện tại

**Căn cứ:** Yêu cầu người dùng đã chốt và implementation hiện có tại `CodexTerminalViewModel.createSession()`.

**Trade-off:** không nhận biết profile/workspace, nhưng đúng scope và tránh tạo dependency nghiệp vụ chưa tồn tại.

### D2 — Rename bằng context menu + dialog

**Căn cứ:** Yêu cầu người dùng chốt thao tác chuột phải; dialog hỗ trợ prefill, cancel và validation rõ hơn inline edit.

**Không chọn inline edit:** phức tạp focus/keyboard hơn và không đúng interaction đã yêu cầu.

### D3 — Title là state của session, mutation qua ViewModel

**Lý do:** title gắn với identity/lifecycle của session; ViewModel là nơi phù hợp cho lookup, validation và mutation có thể test.

**Trade-off:** cần bảo đảm nested observable được View subscribe đúng.

### D4 — Không dùng SwiftTerm `setTerminalTitle`

**Lý do:** callback này là title do process phát ra, có thể liên tục ghi đè tên thủ công và vi phạm rule manual ưu tiên auto/system title.

### D5 — Không persistence

**Căn cứ:** README xác nhận terminal process/tab/output không restore sau restart; task không yêu cầu persistence.

**Trade-off:** tên thủ công mất khi restart, nhưng không cần storage/schema và nhất quán lifecycle hiện tại.

### D6 — Cho phép duplicate, từ chối blank

**Lý do:** UUID bảo đảm identity; cấm duplicate không có business value được yêu cầu. Blank làm tab khó thao tác/accessibility nên bị từ chối.

## 7. Implementation Plan

### Task 1: Viết regression tests cho rename contract

**Mục tiêu:** Khóa hành vi trước khi sửa production.

**Files:**
- Modify: `Tests/OpsHubTests/CodexTerminalViewModelTests.swift`

**Bước:**
1. Thêm test tạo hai session vẫn nhận `Terminal 1`, `Terminal 2`.
2. Rename session đầu khi session thứ hai đang selected; xác minh chỉ session đầu đổi tên và selection không đổi.
3. Xác minh rename không tác động host/terminate count/state.
4. Xác minh input được trim và blank không thay title.
5. Xác minh duplicate title được chấp nhận.
6. Xác minh rename UUID không tồn tại không crash/không đổi session khác.
7. Chạy `swift test --filter CodexTerminalViewModelTests`; expected: tests mới fail vì API chưa tồn tại.

### Task 2: Làm title mutable và observable

**Mục tiêu:** Session phát sự kiện khi title đổi.

**Files:**
- Modify: `Sources/OpsHub/Features/CodexTerminal/Models/CodexTerminalModels.swift`

**Bước:**
1. Chuyển title sang published mutable state với setter được giới hạn phù hợp.
2. Giữ initializer/factory call site tương thích.
3. Không thay đổi state/host/terminate logic.
4. Build để xác minh không tạo source break ngoài phạm vi.

### Task 3: Thêm rename operation tại ViewModel

**Mục tiêu:** Tập trung lookup và validation trong lớp có thể unit test.

**Files:**
- Modify: `Sources/OpsHub/Features/CodexTerminal/ViewModels/CodexTerminalViewModel.swift`

**Bước:**
1. Thêm rename API nhận session UUID và candidate title.
2. Trim whitespace/newline; reject empty.
3. Chỉ mutate session đúng UUID, không đổi selected ID/counter/host/state.
4. Chạy `swift test --filter CodexTerminalViewModelTests`; expected: pass.

### Task 4: Bổ sung context menu và rename dialog

**Mục tiêu:** Hoàn thiện interaction chuột phải theo yêu cầu.

**Files:**
- Modify: `Sources/OpsHub/Features/CodexTerminal/Views/CodexTerminalView.swift`

**Bước:**
1. Tách tab item thành child View quan sát `CodexTerminalSession` nếu cần để title update tức thời đáng tin cậy.
2. Thêm state target session ID và draft title tại parent view.
3. Đặt context menu trên toàn tab container với action `Rename Tab`.
4. Khi action chạy, prefill tên hiện tại và mở dialog.
5. Dialog có TextField, `Cancel`, `Rename`; disable submit khi normalized input rỗng.
6. Submit qua ViewModel, sau đó reset state.
7. Không thay đổi click-to-select hoặc close confirmation flow.
8. Bảo đảm accessibility label dùng title observable mới.

### Task 5: Cập nhật tài liệu

**Mục tiêu:** Contract người dùng khớp behavior mới.

**Files:**
- Modify: `README.md`

**Bước:**
1. Ghi tab mới dùng `Terminal N`.
2. Ghi cách nhấp chuột phải và chọn `Rename Tab`.
3. Giữ rõ session/title không restore qua restart.

### Task 6: Verification toàn diện

**Mục tiêu:** Xác nhận correctness và không regression.

**Automated:**
1. `swift test --filter CodexTerminalViewModelTests`
2. `swift build`
3. `swift test`
4. `swift build -c release`
5. `git diff --check`

**Manual smoke test (`swift run OpsHub`):**
1. Tạo ba tab, xác minh `Terminal 1`, `Terminal 2`, `Terminal 3`.
2. Click phải tab không selected, chọn `Rename Tab`, xác minh draft đúng tab đó.
3. Rename thành `Architect`; xác minh title đổi ngay và selected tab không bị đổi ngoài ý muốn.
4. Tạo tab tiếp theo, xác minh là `Terminal 4`, không phải dựa trên tên manual.
5. Rename hai tab cùng tên; xác minh cả hai vẫn độc lập.
6. Thử blank/whitespace; xác minh không thể xác nhận hoặc title không đổi.
7. Thử tên dài và nhiều tab; xác minh tab strip vẫn scroll và context menu usable.
8. Chạy lệnh trong một tab trước/sau rename; xác minh output, input và process không gián đoạn.
9. Đóng tab đang/không chạy; xác minh close behavior cũ không regression.

## 8. Developer Handoff

Developer chỉ cần thay đổi model, ViewModel, tab UI, unit test và README trong các file đã liệt kê. Không nối SwiftTerm title callback, không thêm persistence, không đổi shell/session factory và không thay packaging. Điểm cần chú ý nhất là nested observation: title đổi phải làm đúng tab redraw ngay, vì parent array không tự publish mutation của child object. Hoàn thành khi unit/full/release build pass và manual smoke test chứng minh rename không tác động terminal process.
