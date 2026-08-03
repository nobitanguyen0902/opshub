# Kanban Task Orchestration Design

## Mục tiêu

Mở rộng Kanban của OpsHub từ màn hình theo dõi thành nơi người dùng có thể:

- tạo một logical task cho Git repository bất kỳ trên máy;
- chủ động bấm **Start** sau khi kiểm tra nội dung;
- tự động chạy toàn bộ workflow `Architect → Developer → Reviewer`;
- theo dõi agent hiện tại, run history, handoff và live log;
- xử lý approval, cancel, retry và reviewer repair loop;
- resume an toàn sau khi đóng và mở lại ứng dụng.

V1 chỉ cho phép chạy khi working tree sạch. OpsHub không commit, push, mở pull request hoặc thực hiện release thay người dùng ngoài contract task được giao.

## Phạm vi V1

### Bao gồm

- Tạo task với Title, Objective, Acceptance Criteria, Workspace Path và Priority.
- Validate Workspace Path tồn tại và là Git repository trước khi tạo draft.
- Tạo task ở trạng thái logical `Triage`; chỉ chạy khi người dùng bấm **Start**.
- Kiểm tra working tree sạch, đủ ba Hermes profile, Hermes CLI khả dụng và Gateway/dispatcher đang chạy trước khi Start.
- Tự điều phối tuần tự Architect, Developer và Reviewer.
- Dừng để xin duyệt khi Architect phát hiện migration, breaking API, credential, release hoặc destructive operation.
- Cancel run đang chạy, Retry stage bị block và tối đa hai Developer repair run sau `changes_requested`.
- Board có sáu cột, cho collapse thủ công từng cột và ghi nhớ lựa chọn.
- Task detail có Overview, Runs và Live Log.
- Resume idempotent sau khi ứng dụng khởi động lại.

### Không bao gồm

- Kéo thả task để thay đổi status.
- Sửa task, bình luận, attachment hoặc archive từ OpsHub.
- Cho phép chạy trên working tree dirty.
- Tự tạo Git worktree.
- Chạy nhiều code-writing workflow đồng thời trong cùng workspace.
- Thay đổi schema `~/.hermes/kanban.db`.
- Routing workflow bằng các field Hermes v2 dự phòng; Hermes hiện chưa dùng các field này để route.

## Kiến trúc

### Ranh giới trách nhiệm

OpsHub là UI và orchestration layer. Hermes sở hữu lifecycle thực thi của từng agent stage.

1. `KanbanView` hiển thị board, header actions, task sheet và right Inspector.
2. `KanbanViewModel` cung cấp snapshot, selection, loading/error state và gọi coordinator.
3. `KanbanWorkflowCoordinator` áp dụng state machine, approval gate, repair limit, cancel/retry và resume.
4. `HermesKanbanCommandService` gọi Hermes CLI bằng argument API, yêu cầu JSON ở các command hỗ trợ và decode response typed.
5. `KanbanWorkflowStore` lưu logical task và quan hệ giữa logical task với các Hermes stage task.
6. Hermes Kanban CLI/Gateway tạo, assign, dispatch, reclaim, block, unblock và lưu run/result/log.

OpsHub không ghi SQLite trực tiếp và không phân tích terminal text để quyết định workflow state.

### Logical task và Hermes stage task

Logical task là card người dùng nhìn thấy trong OpsHub. Trước Start, nó là draft `Triage` trong workflow store và chưa tạo Hermes run.

Mỗi stage hoặc repair attempt là một Hermes task/run riêng:

- Architect task;
- Developer task;
- Reviewer task;
- Developer repair task và Reviewer retry task khi cần.

Stage kế tiếp chỉ được tạo sau khi stage trước có output hợp lệ. Cách tạo lazy này giữ lịch sử stage bất biến, hỗ trợ repair loop và tránh sửa kết quả đã hoàn tất.

Workflow store chỉ lưu mapping và orchestration metadata. Status, assignee, run, result và log của agent luôn lấy từ Hermes JSON.

## Contract dữ liệu

### Logical task

Mỗi record trong workflow store chứa:

- `schemaVersion`;
- logical task ID;
- title;
- objective;
- acceptance criteria;
- workspace path;
- priority;
- created/updated timestamp;
- logical phase;
- current stage;
- approval state;
- repair count;
- danh sách stage reference;
- pending transition và idempotency key.

Priority dùng bốn mức và map ổn định sang số Hermes: `Low = 0`, `Normal = 1`, `High = 2`, `Urgent = 3`. Giá trị lớn hơn được ưu tiên trước, nhất quán với cách board hiện sắp xếp task.

### Stage reference

Mỗi stage reference chứa:

- role: Architect, Developer hoặc Reviewer;
- attempt index;
- Hermes task ID;
- idempotency key;
- timestamp tạo stage.

Không sao chép Hermes status, result hoặc log vào workflow store.

### Lưu trữ

Workflow index được ghi atomic tại:

`Application Support/OpsHub/Kanban/workflows.json`

File không chứa credential. Permission nên giới hạn cho user hiện tại. Trạng thái collapse cột là preference giao diện và được lưu trong `UserDefaults`, tách khỏi workflow data.

## State machine

### Tạo và Start

1. Người dùng nhập Title, Objective, Acceptance Criteria, Workspace Path và Priority.
2. Form chỉ cho tạo khi các field bắt buộc hợp lệ, path tồn tại và là Git repository.
3. OpsHub lưu logical task ở `Triage`.
4. Khi bấm **Start**, OpsHub kiểm tra lại:
   - path vẫn tồn tại và vẫn là Git repository;
   - `git status --porcelain` không có output;
   - các profile Hermes `architect`, `developer` và `reviewer` tồn tại;
   - Hermes CLI khả dụng;
   - `hermes gateway status` kết thúc thành công, chứng minh Gateway/dispatcher đang chạy.
5. Guard thất bại giữ task ở `Triage`, hiển thị lỗi cụ thể và không tạo Hermes task dở dang.
6. Guard đạt thì coordinator tạo Architect task với idempotency key và chuyển logical task sang active workflow.

OpsHub không tự khởi động Gateway trong V1. Nếu Gateway đang dừng, Start hiển thị hướng dẫn người dùng khởi động Hermes Gateway rồi thử lại. Coordinator không gọi global `hermes kanban dispatch` vì command đó có thể dispatch một ready task khác ngoài workflow đang Start.

V1 chỉ cho phép một workflow active trên mỗi canonical workspace path, kể cả khi workflow kia đang ở Architect hoặc Reviewer. Task khác cùng workspace vẫn có thể ở `Triage` nhưng Start bị disable kèm lý do. Canonical path được chuẩn hóa bằng URL resolution trước khi so sánh để tránh chạy song song qua hai spelling của cùng thư mục.

### Architect

Architect là read-only và trả một trong:

- `ready`: tạo Developer task;
- `approval_required`: chuyển logical task sang Approval Required và chờ người dùng;
- `blocked`: chuyển sang Needs Attention.

Approval Required hiển thị lý do và hai thao tác:

- **Approve & Continue**: tạo Developer task;
- **Cancel**: dừng workflow theo semantics Cancel bên dưới.

### Developer

Developer là stage được phép thay đổi code. Kết quả hợp lệ:

- `completed`: tạo Reviewer task;
- `blocked`: chuyển Needs Attention;
- `failed`: dựa trên Hermes failure/retry state và chỉ cho Retry khi stage đã về trạng thái recoverable.

### Reviewer và repair loop

Reviewer là read-only và trả:

- `approved`: logical task chuyển Done;
- `changes_requested`: tạo Developer repair task, sau đó tạo Reviewer retry task;
- `blocked`: chuyển Needs Attention.

Cho phép tối đa hai Developer repair run sau lần review đầu tiên. Khi Reviewer tiếp tục yêu cầu thay đổi sau giới hạn này, logical task chuyển Needs Attention. Retry một run lỗi không reset repair count.

### Cancel

Nếu có Hermes run đang chạy:

1. gọi `hermes kanban reclaim <task-id> --reason "Cancelled by user"`;
2. khi reclaim thành công, gọi `hermes kanban block <task-id> --kind needs_input "Cancelled by user"`;
3. chỉ báo Cancel thành công sau khi cả hai bước đã được reconcile.

Nếu reclaim thành công nhưng block thất bại, logical task chuyển Needs Attention và hiển thị recovery action; không báo thành công sai.

Nếu chưa có active run, Cancel dừng transition hiện tại và giữ audit reason trong logical workflow record.

Task bị Cancel xuất hiện ở cột Blocked với reason `Cancelled by user`. Nếu Cancel xảy ra tại Approval Required hoặc giữa hai stage, **Retry** khôi phục phase recoverable ngay trước Cancel; riêng Approval Required quay lại gate và vẫn cần người dùng chọn Approve & Continue.

### Retry

Retry có hai trường hợp explicit:

- Nếu current Hermes stage đang blocked/recoverable, coordinator gọi `hermes kanban unblock` cho cùng stage task; Hermes tạo run attempt mới và giữ lịch sử cũ.
- Nếu workflow bị Cancel khi không có active Hermes run, coordinator khôi phục phase đã lưu trước Cancel và tiếp tục bằng idempotency key hiện có. Approval Required quay lại gate thay vì tự duyệt.

Retry không xóa handoff/log cũ và không reset reviewer repair count.

## Structured handoff

Mỗi profile phải trả outcome, summary và metadata theo contract của stage. Coordinator chỉ chuyển stage khi:

- command kết thúc thành công;
- Hermes task/run ở terminal state phù hợp;
- outcome hợp lệ với role;
- required metadata decode được.

Output thiếu, sai enum hoặc mâu thuẫn với Hermes terminal state chuyển logical task sang Needs Attention. Không suy luận state từ câu chữ trong log.

Metadata tối thiểu dùng `schemaVersion = 1`:

- Architect: `outcome`, `summary`, `risks`;
- Developer: `outcome`, `summary`, `changedFiles`, `verification`;
- Reviewer: `outcome`, `summary`, `findings`.

`risks`, `changedFiles`, `verification` và `findings` là array, có thể rỗng nhưng không được thiếu. Stage prompt yêu cầu profile hoàn tất Hermes task với summary và metadata này; coordinator đọc metadata từ latest terminal run.

## Idempotency và resume

Trước mutation, workflow store ghi `pendingTransition` bằng atomic write. Mỗi stage creation dùng idempotency key theo logical task ID, stage và attempt.

Sau mutation, coordinator đọc lại `hermes kanban show --json` và `runs --json`, cập nhật stage reference rồi xóa pending transition.

Khi ứng dụng khởi động lại:

1. load workflow index;
2. reconcile từng active workflow với Hermes;
3. hoàn tất pending transition nếu Hermes đã nhận lệnh;
4. retry bằng cùng idempotency key nếu Hermes chưa tạo task;
5. chuyển Needs Attention nếu response không thể reconcile an toàn.

Không tự tạo stage trùng và không tự đoán một run đã thành công khi thiếu evidence.

## UI và tương tác

### Feature header

Header hiển thị title/subtitle bên trái. Bên phải gồm **Refresh** và primary action **New Task**. Header không cuộn ngang theo board.

### Board và collapse

Giữ sáu cột Kanban. Mỗi cột có chevron collapse riêng:

- collapse do người dùng điều khiển, không tự thay đổi theo số task;
- OpsHub ghi nhớ lựa chọn giữa các lần mở app;
- cột collapsed vẫn hiển thị title, task count và màu cảnh báo;
- không dùng focus mode chỉ mở một cột.

Projection từ Hermes status sang sáu cột là explicit:

- `triage` → Triage;
- `todo` và `scheduled` → Todo;
- `ready` → Ready;
- `running` và `review` → Running;
- `blocked` → Blocked;
- `done` → Done;
- `archived` không xuất hiện trên board mặc định.

Logical task do OpsHub tạo dùng logical phase để chọn cột. Trong cột Running, card luôn hiển thị current stage nên Reviewer không bị trình bày như Developer.

### New Task sheet

Form gồm:

- Title;
- Objective;
- Acceptance Criteria, một tiêu chí có thể kiểm chứng trên mỗi dòng;
- Workspace Path với Browse;
- Priority.

Task luôn được tạo ở Triage. Form không có Create & Start trong V1.

### Card

Card chỉ hiển thị:

- priority và logical task ID;
- title;
- agent/stage hiện tại và elapsed time;
- workspace basename.

Không đặt mutation action trực tiếp trên card. Click card mở right Inspector.

### Right Inspector

Inspector giữ board và scroll position phía sau, gồm:

- Overview;
- Runs;
- Live Log.

Action theo state:

- Triage: Start;
- Running: Cancel;
- Blocked/recoverable: Retry;
- Approval Required: Approve & Continue hoặc Cancel;
- Done: không có mutation action.

Escape hoặc × đóng sheet/Inspector và trả focus về control đã mở nó. Live Log chỉ tự cuộn khi người dùng đang ở cuối log.

### Hermes task ngoài OpsHub workflow

Task Hermes có sẵn vẫn xuất hiện trên board và cho xem detail/log. Start, approval, workflow Cancel/Retry chỉ áp dụng cho logical task có workflow index do OpsHub tạo; OpsHub không nhận quyền điều phối task ngoài workflow một cách ngầm định.

## Đọc dữ liệu Hermes

Board và detail chuyển sang dùng Hermes CLI JSON thay vì truy vấn SQLite trực tiếp:

- `hermes kanban list --json`;
- `hermes kanban show <id> --json`;
- `hermes kanban runs <id> --json`;
- `hermes kanban log <id> --tail <bytes>` cho log text hiển thị, không dùng log để quyết định state.

`KanbanSQLiteReader` không còn là runtime dependency sau migration này. Regression test mới phải chứng minh board/detail lấy dữ liệu từ CLI fixtures trước khi xóa hoặc retire reader và các test SQLite cũ.

Mutation dùng command Hermes tương ứng với argument array. Không ghép title, body hoặc path trực tiếp thành shell command. `HermesKanbanCommandService` map lỗi shell hiện có sang `KanbanCommandError` để không hiển thị thông báo Homebrew sai ngữ cảnh.

## Xử lý lỗi

- Refresh lỗi giữ snapshot gần nhất và hiển thị banner.
- Form validation lỗi hiển thị cạnh field; không tạo draft.
- Start guard lỗi giữ Triage và hiển thị nguyên nhân cụ thể.
- CLI exit khác 0 hiển thị domain error và stderr đã sanitize trong command detail.
- JSON không hợp lệ hoặc thiếu field bắt buộc được coi là compatibility error.
- Store write thất bại chặn mutation để không tạo trạng thái Hermes không có mapping.
- Handoff sai contract chuyển Needs Attention.
- Action đang chạy bị disable để chống double submit.
- Cancellation của Swift task không được coi là Hermes Cancel; chỉ thao tác Cancel rõ ràng mới reclaim worker.

## Kiểm thử

### Unit tests

- Form validation cho required fields, path không tồn tại và non-Git directory.
- Start guard cho clean/dirty repository, thiếu profile, thiếu Hermes CLI và Gateway đang dừng.
- Argument construction và shell escaping cho title, body và workspace path.
- JSON decoding cho list, show, runs và create/mutation responses.
- Happy path Architect → Developer → Reviewer → Done.
- Architect approval required và resume sau Approve & Continue.
- Architect/Developer/Reviewer blocked paths.
- Cancel thành công và partial failure giữa reclaim/block.
- Retry tạo attempt mới và giữ lịch sử.
- Reviewer changes requested và giới hạn hai repair run.
- App restart ở từng pending transition và idempotent reconciliation.
- Workflow store atomic write, missing file, incompatible schema version và corrupt file.
- Collapse preference save/restore.
- View model chống mutation trùng và giữ snapshot khi refresh lỗi.

### Integration boundaries

Test dùng fake/stub command runner và fixture JSON; không gọi agent, gateway hoặc network thật. Thêm contract fixtures từ output Hermes CLI hiện hành để phát hiện field rename hoặc enum mới.

### Verification gates

Chạy từ repository root:

```bash
swift test --filter Kanban
swift test
swift build
swift build -c release
git diff --check
```

Compiler/test không thay thế visual QA. Trước bàn giao cần chạy app từ bundle vừa build, kiểm tra New Task sheet, collapse persistence, Inspector, approval action và log scrolling.

## Tương thích và rollout

- Không migrate hoặc ghi trực tiếp `kanban.db`.
- Workflow store có `schemaVersion`; phiên bản không hỗ trợ phải báo lỗi thay vì decode một phần.
- Khi Hermes CLI thiếu command/JSON field bắt buộc, Kanban chuyển read-only compatibility state và không cho mutation.
- Task Hermes ngoài OpsHub workflow vẫn đọc được.
- V1 không dựa vào workflow routing field dự phòng của Hermes v2.
- Nếu workflow store bị mất, OpsHub không tự nhận ownership của task Hermes còn lại; người dùng vẫn xem được các task đó như external tasks.

## Tiêu chí hoàn thành

- Người dùng tạo được logical task hợp lệ ở Triage.
- Start bị chặn rõ ràng trên dirty workspace hoặc Gateway đang dừng và không tạo Hermes stage task.
- Clean workspace chạy tuần tự Architect, Developer và Reviewer mà không cần điều phối profile thủ công.
- Approval Required dừng đúng chỗ và chỉ tiếp tục sau khi duyệt.
- Cancel/Retry giữ audit và run history trung thực.
- Reviewer repair loop dừng ở Needs Attention sau hai repair run.
- App restart không tạo trùng stage và resume được workflow đang chạy.
- Collapse state, board scroll context và Inspector interaction hoạt động như thiết kế đã duyệt.
