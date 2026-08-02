# Codex Terminal Workspace — Technical Design

> **Latest scope decision (supersedes workspace requirements below):** Bỏ toàn bộ chức năng chọn, lưu và đổi workspace. Khi mở tab, terminal bắt đầu tại home directory của người dùng. Người dùng tự nhập `cd <path>` hoặc command truy cập workspace trong terminal. Các phần `CodexWorkspaceStore`, `NSOpenPanel`, workspace persistence/bookmark, workspace validation, workspace header và confirmation khi đổi workspace trong tài liệu bên dưới không còn thuộc phạm vi triển khai.

### Final launch flow

1. Người dùng mở feature `Agents`.
2. Người dùng chọn một agent preset hoặc tạo terminal thường.
3. OpsHub tạo một PTY tab độc lập tại home directory của người dùng.
4. Nếu chọn agent preset, OpsHub chạy đúng command của preset (`architect`, `developer`, `reviewer`, ...); nếu là terminal thường, OpsHub chỉ mở login shell.
5. Người dùng tự gõ `cd`, command mở project hoặc các lệnh khác trong terminal.

### Final minimal scope

- Không có workspace model/store/picker.
- Không quản lý hoặc hiển thị current working directory ở cấp SwiftUI; shell/agent tự quản lý cwd trong PTY.
- Không tự động thêm `cd`, `--worktree`, prompt hoặc arguments ngoài cấu hình preset.
- Mỗi tab có PTY/process độc lập; tab nền tiếp tục chạy.
- Việc đóng tab/app vẫn phải terminate và cleanup process.
- Agent preset tối thiểu gồm `id`, `displayName`, `command`, optional `arguments` và `systemImage`.
- Home directory phải lấy từ `FileManager.default.homeDirectoryForCurrentUser`, không hardcode đường dẫn người dùng.

> **Superseded historical requirement:** Thiết kế trước đây yêu cầu chọn workspace trước khi mở terminal. Yêu cầu này đã bị thay thế bởi “Latest scope decision” ở trên và không được triển khai.

### Historical launch contract — không triển khai

- Trạng thái chưa chọn workspace: không có terminal; các hành động mở agent bị vô hiệu hóa và UI chỉ cung cấp `Choose Workspace`.
- Trạng thái đã chọn workspace: hiển thị danh sách/nút agent, ví dụ `Architect`, `Developer`, `Reviewer`.
- Mỗi agent preset chỉ ánh xạ tới một command có sẵn, ví dụ alias Hermes `architect`, `developer`, `reviewer`. Alias là command do Hermes profile tạo và tương đương `hermes -p <profile>`.
- Khi người dùng chọn agent, OpsHub tạo một tab PTY mới, đặt working directory bằng workspace đã chọn và gọi đúng executable/command của agent đó.
- Không tự thêm `--worktree`, prompt ban đầu, arguments hoặc orchestration nếu preset chưa cấu hình chúng; command của agent là nguồn quyết định hành vi.
- Có thể mở nhiều tab của cùng hoặc khác agent. Mỗi tab vẫn là một PTY/process độc lập nhưng cùng working directory.
- Đổi workspace khi đang có terminal tiếp tục tuân theo confirmation/terminate rule trong tài liệu này.

### Agent preset tối thiểu

`AgentPreset` chỉ cần `id`, `displayName`, `command` và `systemImage`. `workingDirectory` không nằm trong preset mà luôn lấy từ workspace selection cấp feature. Arguments là tùy chọn để mở rộng sau này, không cần cho các alias Hermes ở V1.

## 1. Solution Summary

> Áp dụng phạm vi cuối cùng ở đầu tài liệu: terminal mở tại home directory và người dùng tự điều hướng bằng command. Không triển khai workspace selection dù các phân tích lịch sử bên dưới còn nhắc tới workspace.

Thêm feature `Codex` vào sidebar của OpsHub. Người dùng chọn một workspace directory; trong feature này họ có thể tạo nhiều tab terminal độc lập. Mỗi tab dùng SwiftTerm `LocalProcessTerminalView`, khởi chạy một PTY tại workspace đã chọn và tự chạy Codex CLI. Các tab hỗ trợ tương tác terminal đầy đủ: ANSI/color, resize, nhập liệu liên tục, Ctrl+C và process lifecycle độc lập.

Thiết kế phiên bản đầu chỉ quản lý session trong bộ nhớ. Workspace gần nhất được lưu để tái sử dụng, nhưng terminal process và nội dung terminal không được restore sau khi ứng dụng khởi động lại.

## 2. Requirement Understanding

### Mục tiêu

- Cung cấp môi trường chạy nhiều Codex agent song song ngay trong OpsHub.
- Mỗi agent chạy trong một terminal tab độc lập và cùng bắt đầu tại workspace do người dùng chọn.
- Terminal phải là PTY tương tác đầy đủ, không phải command log hoặc shell runner một lần.

### Phạm vi đã chốt

- Một menu feature mới trong sidebar: `Codex`.
- Người dùng chọn một directory làm workspace.
- Có thể mở nhiều terminal tab.
- Mỗi tab tự chạy command `codex`.
- Mỗi terminal hỗ trợ ANSI, resize, Ctrl+C và nhập liệu tương tác.
- Sử dụng SwiftTerm.

### Ngoài phạm vi phiên bản đầu

- Agent ngoài Codex.
- Command tùy chỉnh hoặc cấu hình arguments/env từ UI.
- Nhiều workspace đồng thời trong cùng một cửa sổ.
- Khôi phục process/tab/output sau khi restart ứng dụng.
- Split panes, session sharing, remote SSH và shell history riêng.
- Điều khiển Terminal.app/iTerm/Warp.

### Giả định được ghi rõ

- Command khởi chạy mặc định là `codex`, được resolve qua login shell của người dùng thay vì hardcode đường dẫn cài đặt.
- Tất cả tab hiện tại thuộc workspace đang chọn.
- Đổi workspace khi còn session đang chạy phải yêu cầu người dùng đóng/terminate các session trước; không âm thầm chuyển working directory của process đang chạy.
- Workspace gần nhất được lưu. Vì bundle hiện không có App Sandbox entitlement trong luồng packaging đã kiểm tra, phiên bản hiện tại có thể lưu URL/path. Tuy vậy store nên có contract cho bookmark data để không khóa kiến trúc nếu sandbox được bật sau này.
- Khi đóng tab đang chạy, UI phải xác nhận trước khi terminate để tránh mất công việc Codex đang thực hiện.

### Acceptance Criteria đề xuất

1. Sidebar hiển thị `Codex` mà không làm thay đổi các feature hiện tại.
2. Khi chưa có workspace, màn hình hiển thị empty state và hành động chọn folder.
3. Chỉ directory tồn tại, có thể truy cập mới được chấp nhận làm workspace.
4. Tạo tab mới khởi chạy một PTY độc lập tại workspace và tự chạy Codex CLI.
5. Có thể tạo và tương tác với ít nhất hai tab đồng thời; input/output/process không lẫn nhau.
6. Terminal hiển thị ANSI/color, nhận resize và xử lý Ctrl+C qua PTY.
7. Tab thể hiện trạng thái starting/running/exited/failed và exit code khi có.
8. Đóng tab đang chạy có xác nhận; xác nhận đóng sẽ terminate process và giải phóng PTY.
9. Thoát app hoặc giải phóng feature sẽ terminate toàn bộ process con, không để process Codex mồ côi.
10. Nếu `codex` không resolve hoặc launch thất bại, tab hiển thị lỗi có thể hành động lại, không crash app.
11. Workspace gần nhất được tải lại khi app mở lại nếu vẫn hợp lệ; nếu không hợp lệ, người dùng được yêu cầu chọn lại.

## 3. Technical Design

### Kiến trúc tổng thể

Giữ feature độc lập dưới `Sources/OpsHub/Features/CodexTerminal` và không tái sử dụng `ShellCommandRunner` cho PTY. `ShellCommandRunner` hiện dùng `Process` + pipes, có timeout mặc định và thu output sau khi process kết thúc; contract này không phù hợp process terminal tương tác dài hạn.

Các lớp trách nhiệm:

1. `CodexTerminalView`
   - Composition root cấp feature.
   - Hiển thị feature header, workspace selector, tab strip, terminal đang chọn và empty/error states.
   - Không trực tiếp tạo process.

2. `CodexTerminalViewModel` (`@MainActor`, `ObservableObject`)
   - Sở hữu danh sách session descriptors, selected tab, workspace và presentation state.
   - Điều phối tạo/chọn/đóng/retry tab.
   - Áp business rules khi đổi workspace hoặc đóng session đang chạy.
   - Không chứa terminal renderer hoặc PTY primitives.

3. `CodexTerminalSession`
   - Model tham chiếu có identity ổn định (`UUID`).
   - Chứa title, creation order/time, lifecycle state và exit metadata.
   - Sở hữu một terminal host/session adapter độc lập.
   - Lifecycle state: `starting`, `running`, `exited(code)`, `failed(message)`, `terminating`.

4. `CodexTerminalSessionCreating` / production factory
   - Tạo session với workspace URL và launch specification.
   - Cho phép ViewModel test bằng fake factory mà không spawn process.
   - Đảm bảo một factory call tương ứng một PTY độc lập.

5. `CodexTerminalHostView`
   - `NSViewRepresentable` bridge giữa SwiftUI và SwiftTerm AppKit view.
   - Tạo/cập nhật `LocalProcessTerminalView`, forward process termination event về session model.
   - Đồng bộ size/focus theo lifecycle SwiftUI; SwiftTerm chịu trách nhiệm ANSI, key handling và PTY resize.
   - Identity của host phải gắn với session ID để chuyển tab không tạo lại process.

6. `CodexWorkspaceStore`
   - Load/save/clear workspace selection.
   - Xác thực URL là directory và còn truy cập được.
   - Persist metadata/bookmark theo contract; không lưu secret.

7. `CodexLaunchConfiguration`
   - Tập trung executable shell, command và environment strategy.
   - V1 dùng login shell `/bin/zsh -l` để chạy `codex` tại workspace, giúp resolve PATH từ môi trường người dùng.
   - Command/arguments được truyền theo API dạng mảng nếu SwiftTerm hỗ trợ; không ghép input từ người dùng thành chuỗi shell.

### Luồng chọn workspace

1. Người dùng vào feature `Codex`.
2. ViewModel load workspace gần nhất qua store.
3. Nếu không có/không hợp lệ, hiển thị empty state.
4. `Choose Workspace` mở `NSOpenPanel` với `canChooseDirectories = true`, không chọn file và chỉ chọn một directory.
5. Store lưu selection; ViewModel cập nhật workspace.
6. Feature không tự tạo tab cho tới khi người dùng nhấn `New Agent`, tránh side effect bất ngờ ngay sau folder selection.

### Luồng tạo tab/agent

1. Người dùng chọn `New Agent` hoặc nút `+`.
2. ViewModel yêu cầu factory tạo session với workspace hiện tại và Codex launch configuration.
3. Session được thêm vào collection và chọn làm active tab.
4. Host tạo SwiftTerm local process PTY với working directory đã chọn.
5. Login shell khởi chạy `codex`; terminal nhận output và input trực tiếp qua PTY.
6. Callback của SwiftTerm cập nhật state khi process chạy, exit hoặc launch thất bại.

### Quản lý nhiều tab

- Mỗi tab giữ nguyên host/session instance dù không được chọn; chỉ terminal đang chọn được render/foreground, nhưng process của các tab nền tiếp tục chạy.
- Không tái tạo `LocalProcessTerminalView` khi đổi tab.
- Title mặc định theo thứ tự (`Codex 1`, `Codex 2`, ...), có indicator trạng thái.
- Collection và selected ID thuộc ViewModel; PTY ownership thuộc session.
- Không giới hạn cứng số tab trong V1. UI có thể cảnh báo tài nguyên về sau, nhưng không bổ sung policy chưa có requirement.

### Đổi workspace

- Nếu không có session đang chạy: lưu workspace mới và áp dụng cho tab tạo sau đó; các tab đã exit có thể được đóng hoặc giữ lịch sử theo UI.
- Nếu có session đang chạy: chặn thay đổi và hiển thị confirmation mô tả toàn bộ session sẽ bị terminate. Chỉ đổi sau khi người dùng xác nhận và cleanup hoàn tất.
- Không thay đổi `cwd` của process đang tồn tại vì điều đó tạo trạng thái UI/process không nhất quán.

### Process termination và app lifecycle

- Close tab: nếu running/starting, yêu cầu xác nhận; sau đó gửi terminate thông qua SwiftTerm/local process API và release host sau callback hoặc timeout cleanup ngắn.
- Ctrl+C: để SwiftTerm chuyển control sequence qua PTY; không map thành `Process.terminate()`.
- App termination: session manager terminate toàn bộ child process. Hook cleanup tại owner cấp Scene/App thay vì chỉ `onDisappear`, vì việc đổi sidebar không được giết agent nền.
- Nếu process tự exit, giữ tab và output để người dùng đọc; cho phép Retry tạo process mới trong cùng workspace hoặc tạo tab mới theo UI decision.

### Dependency integration

- Thêm Swift Package `https://github.com/migueldeicaza/SwiftTerm` vào `Package.swift` và link product phù hợp với target `OpsHub`.
- Pin bằng semantic version range từ release ổn định đã được kiểm tra lúc triển khai; `Package.resolved` ghi chính xác revision.
- SwiftTerm được xác nhận từ upstream là VT100/Xterm emulator, có AppKit frontend, `LocalProcessTerminalView`, dùng Swift Package Manager và MIT license.
- Trước implementation phải kiểm tra API/tag cụ thể của phiên bản được pin vì API trên branch `main` không phải contract phát hành.

### UI composition

- Sidebar thêm `AppSection.codex` với icon terminal phù hợp.
- Header tái sử dụng `OpsHubFeatureHeader`, metadata hiển thị workspace và số session active.
- Controls: `Choose/Change Workspace`, `New Agent`.
- Tab strip đặt ngay trên terminal surface; mỗi tab có title, status dot và close action.
- Terminal chiếm phần còn lại của detail view và phải nhận keyboard focus khi tab được chọn/tạo.
- Màu terminal ưu tiên theme/profile của SwiftTerm được map gần `OpsHubTerminalTheme`, nhưng không thay đổi terminal ANSI palette theo cách làm sai output của CLI.

## 4. Impact Analysis

### Module / files

- `Package.swift`: thêm SwiftTerm package/product.
- `Package.resolved`: revision dependency mới.
- `Sources/OpsHub/App/ContentView.swift`: thêm `AppSection.codex`, label/icon và route tới feature.
- `Sources/OpsHub/App/OpsHubApp.swift`: inject workspace store/session owner nếu cleanup cần lifecycle cấp app.
- Tạo `Sources/OpsHub/Features/CodexTerminal/Models`: workspace, launch configuration, session state.
- Tạo `Sources/OpsHub/Features/CodexTerminal/Services`: workspace store và session factory abstractions.
- Tạo `Sources/OpsHub/Features/CodexTerminal/ViewModels`: tab/workspace/session orchestration.
- Tạo `Sources/OpsHub/Features/CodexTerminal/Views`: feature screen, tab strip và SwiftTerm AppKit bridge.

### API

- Không thay đổi network API hoặc public external API.
- Có internal contracts mới cho workspace persistence và session creation.

### Database / cache / event

- Không có database, cache hoặc event bus mới.
- Persist workspace metadata/bookmark trong UserDefaults hoặc store tương đương.
- Không persist terminal output.

### Config / permissions

- Không lưu token/credential Codex trong OpsHub; Codex CLI tự dùng cơ chế đăng nhập/config hiện có của nó.
- `NSOpenPanel` là user-mediated access.
- Nếu tương lai bật App Sandbox, phải dùng security-scoped bookmark và giữ scope trong suốt session; đây là compatibility constraint cần ghi lại.

### Dependency / packaging

- Thêm SwiftTerm làm runtime dependency.
- Packaging script hiện chỉ copy `Sparkle.framework`. Developer phải kiểm tra output của SwiftPM: nếu SwiftTerm link động, script phải copy framework và codesign theo thứ tự; nếu static, không cần bước copy. Không sửa packaging theo giả định.
- Release build, ad-hoc signing và Developer ID signing đều cần được xác minh.
- Ghi nhận MIT license vào tài liệu third-party notices nếu project áp dụng.

### Infrastructure / CI

- SwiftPM cần fetch dependency mới trong CI.
- Không cần service hoặc infrastructure backend.

### Test

- Update `Tests/OpsHubTests/AppSectionTests.swift` cho thứ tự/metadata sidebar mới.
- Unit tests mới cho workspace validation/persistence.
- Unit tests mới cho ViewModel: create/select/close/retry session, unique identities, workspace guards, factory failures và cleanup.
- Unit tests cho launch specification: workspace và Codex command được truyền đúng, không shell-inject path.
- Integration/manual tests bắt buộc cho PTY: ANSI, resize, Ctrl+C, focus, Unicode, multiple concurrent tabs và process exit.
- Packaging smoke test để xác nhận app archive launch được và load SwiftTerm runtime thành công.

### Documentation

- README: dependency/build note, prerequisite `codex` CLI, cách chọn workspace và lifecycle session.
- Nếu có release notes: nêu session không được restore qua app restart.

## 5. Risk Analysis

| Rủi ro | Mức độ | Nguyên nhân | Giảm thiểu |
|---|---|---|---|
| Process mồ côi khi đóng tab/app | Cao | PTY/process sống dài hạn và nhiều owner UI | Session owner duy nhất, explicit terminate, app lifecycle cleanup, test process exit |
| PATH không tìm thấy `codex` | Cao | GUI app không thừa hưởng shell PATH như Terminal | Khởi chạy qua login shell, hiển thị launch error rõ ràng, kiểm tra command availability trước hoặc trong tab |
| Mất công việc khi đóng tab/đổi workspace | Cao | Terminate agent đang chạy | Confirmation cho session running; không âm thầm terminate |
| Process bị tạo lại khi đổi tab | Cao | SwiftUI view identity/reconciliation | Stable session IDs, host ownership trong session, test tab switching |
| Packaging thiếu SwiftTerm runtime | Cao nếu dynamic | Script hiện chỉ copy Sparkle | Kiểm tra linkage thực tế bằng build artifact/`otool`, cập nhật packaging chỉ khi cần, smoke test archive |
| Main-thread blocking | Trung bình | PTY callbacks/output volume lớn | SwiftTerm handles IO; chỉ publish state nhỏ trên main actor, không mirror toàn bộ output vào SwiftUI state |
| Memory/CPU tăng theo số tab | Trung bình | Nhiều Codex process và terminal scrollback | Cleanup dứt điểm; dùng scrollback hợp lý; quan sát tài nguyên, chưa áp hard limit khi chưa có requirement |
| Workspace access mất sau restart/sandbox | Trung bình | Persist path không đảm bảo quyền lâu dài | Store abstraction và bookmark-ready design; validate mỗi lần load |
| Shell startup config gây side effect | Trung bình | `/bin/zsh -l` load user profile | Dùng để resolve PATH trong V1; log/hiển thị launch failure; cân nhắc executable resolver ở phiên bản sau |
| API SwiftTerm thay đổi | Trung bình | Upstream active, `main` không ổn định | Pin release, adapter cô lập dependency, không để SwiftTerm types lan vào ViewModel/domain |
| Ctrl+C bị hiểu là terminate toàn session | Trung bình | Mapping sai ở host layer | Forward keyboard input qua PTY; chỉ close action gọi terminate API |
| Command/path injection | Thấp–Trung bình | Ghép workspace/command thành shell string | Truyền working directory riêng và argv; command Codex là constant, không nội suy input người dùng |

## 6. Decision Log

### D1 — Dùng SwiftTerm thay vì tự viết terminal hoặc AppleScript

- Lý do: requirement cần terminal PTY đầy đủ. SwiftTerm cung cấp VT100/Xterm engine, AppKit frontend và local process terminal.
- Không chọn tự viết PTY: chi phí/rủi ro ANSI, input, resize, Unicode và lifecycle quá lớn.
- Không chọn Terminal.app automation: không tích hợp tab/session vào OpsHub và thêm quyền Automation.
- Trade-off: thêm dependency runtime và trách nhiệm packaging/version management.

### D2 — Không reuse `ShellCommandRunner`

- Căn cứ source: runner hiện chạy `/bin/zsh -lc`, dùng pipes, timeout và chờ process exit rồi mới trả result.
- Lý do: contract request/response ngắn hạn không phù hợp PTY tương tác và agent sống dài hạn.
- Trade-off: thêm session abstraction mới, nhưng tránh làm hỏng hành vi Brew đang dùng runner.

### D3 — Một PTY độc lập cho mỗi tab

- Lý do: bảo đảm agent, stdin/stdout, cwd và lifecycle không lẫn nhau.
- Không chọn multiplex nhiều agent trong một shell: khó xác định ownership, cancellation và UI state.
- Trade-off: sử dụng nhiều tài nguyên hơn nhưng đúng semantic “nhiều agent song song”.

### D4 — Session in-memory, workspace persisted

- Lý do: process không thể khôi phục trung thực sau app restart; chỉ restore tab giả sẽ gây hiểu nhầm.
- Trade-off: người dùng mất tab list/output khi restart, nhưng lifecycle rõ ràng và đáng tin cậy.

### D5 — Codex command qua login shell trong V1

- Lý do: GUI app thường không có PATH giống interactive Terminal; Codex thường được cài bởi user toolchain/package manager.
- Không chọn hardcode path: không portable giữa Homebrew, npm và toolchain manager.
- Trade-off: shell profile có thể chậm hoặc có side effect; adapter cho phép thay strategy về sau.

### D6 — Chặn đổi workspace khi session đang chạy trừ khi xác nhận terminate

- Lý do: cwd của process hiện tại không thể được đổi an toàn từ UI và agent có thể đang sửa file.
- Trade-off: thêm một bước xác nhận nhưng ngăn data loss/trạng thái không nhất quán.

## 7. Implementation Plan

1. Xác minh release/API SwiftTerm sẽ pin
   - Thành phần: `Package.swift`, upstream tag/API/license.
   - Kết quả: version cụ thể, product name, local-process API, callbacks, termination và dynamic/static linkage được xác nhận.

2. Bổ sung regression test cho navigation
   - Thành phần: `Tests/OpsHubTests/AppSectionTests.swift`.
   - Kết quả: test thất bại trước khi thêm `Codex`, xác định rõ thứ tự/title/icon.

3. Xác định terminal start directory
   - Thành phần: session factory và tests.
   - Kết quả: terminal bắt đầu tại `FileManager.default.homeDirectoryForCurrentUser`; không có workspace persistence hoặc folder picker.

4. Thiết kế và test session orchestration
   - Thành phần: session state, factory protocol, `CodexTerminalViewModel`, fake factory.
   - Kết quả: create/select/close/retry/multiple tabs/workspace guard/cleanup có unit test, chưa phụ thuộc SwiftTerm UI.

5. Tạo SwiftTerm adapter và local-process factory
   - Thành phần: `NSViewRepresentable`, production session factory, launch configuration.
   - Kết quả: mỗi session tạo đúng một PTY, cwd đúng workspace, tự chạy `codex`, termination callback cập nhật state.

6. Xây UI feature Codex
   - Thành phần: feature view, empty state, workspace picker, feature header, tab strip, terminal surface và confirmation dialogs.
   - Kết quả: luồng end-to-end trong app hoàn chỉnh, focus và status dễ hiểu.

7. Tích hợp sidebar và app lifecycle
   - Thành phần: `ContentView`, `OpsHubApp`, session owner cleanup.
   - Kết quả: feature truy cập được từ sidebar; chuyển feature không giết session; thoát app không để process mồ côi.

8. Xử lý lỗi và accessibility
   - Thành phần: missing Codex, invalid workspace, launch/exit states, labels/focus/keyboard.
   - Kết quả: lỗi actionable, không crash; tab và controls có accessibility labels.

9. Kiểm tra package/release impact
   - Thành phần: SwiftPM artifact, packaging script nếu linkage yêu cầu, signing.
   - Kết quả: debug/release app load SwiftTerm được; chỉ sửa packaging khi artifact inspection chứng minh cần thiết.

10. Validation đầy đủ
    - Chạy `swift test --filter AppSectionTests` và test filters mới.
    - Chạy `swift build`, `swift test`, `swift build -c release`, `git diff --check`.
    - Manual: chọn workspace có khoảng trắng/Unicode; mở ít nhất hai Codex tabs; nhập đồng thời; ANSI; resize; Ctrl+C; switch tab; process exit; close confirmation; quit cleanup.
    - Nếu có package artifact: chạy packaged app smoke test và kiểm tra dynamic linkage/signature.

11. Cập nhật documentation
    - Thành phần: README và third-party notice nếu áp dụng.
    - Kết quả: prerequisite Codex, cách dùng, persistence limitation và dependency license được mô tả.

## 8. Developer Handoff

Developer triển khai feature mới theo boundary `Features/CodexTerminal`; không mở rộng `ShellCommandRunner` và không để SwiftTerm types lan vào domain/ViewModel. Tạo workspace store, session factory và lifecycle model có thể fake trong test trước; sau đó bridge SwiftTerm qua AppKit/SwiftUI. Mỗi tab phải giữ một PTY instance ổn định và độc lập. Workspace được persist/validate, còn process/tab/output chỉ tồn tại trong phiên chạy hiện tại. Việc đóng tab, đổi workspace và thoát app phải cleanup process có chủ đích; không được coi Ctrl+C là đóng process. Trước khi sửa packaging, kiểm tra linkage artifact thực tế của SwiftTerm.

Điểm cần xác nhận trong lúc implementation, không làm thay đổi thiết kế nghiệp vụ: tag/API SwiftTerm cụ thể, product linkage static/dynamic và callback lifecycle của `LocalProcessTerminalView` ở phiên bản được pin.