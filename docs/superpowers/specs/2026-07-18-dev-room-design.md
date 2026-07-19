# Thiết kế Dev Room

**Ngày:** 2026-07-18  
**Trạng thái:** Chờ user review  
**Phạm vi:** Thêm một menu cấp cao và một màn hình Dev Room độc lập trong OpsHub.

## 1. Mục tiêu

Dev Room trực quan hóa các GitLab issue đang mở của một Project dưới dạng phòng làm việc. Mỗi nhân viên đang có task xuất hiện đúng một lần tại một bàn; card của nhân viên cho biết tổng workload và số task ở từng bước workflow.

Màn hình dùng GitLab làm nguồn dữ liệu duy nhất và chỉ đọc dữ liệu. Dev Room không thay đổi label, assignee hoặc trạng thái issue.

## 2. Quyết định đã chốt

- Dev Room là một `AppSection` mới và một màn hình mới, không thay thế màn hình GitLab hiện tại.
- Giữ nguyên Dashboard, Brew, GitLab, Settings và toàn bộ tab, filter, API behavior hiện có.
- Project của Dev Room phiên bản đầu là workflow Project hiện tại: `social/socom-issues`.
- Header chỉ hiển thị tên Project cố định; không có Project picker.
- Chỉ lấy GitLab issue có trạng thái `opened`.
- Chỉ lấy issue có đúng ngữ nghĩa của ít nhất một label: `Todo`, `Doing`, `ToTest`, `Testing`, `Passed`.
- So khớp label không phân biệt hoa thường và bỏ khoảng trắng đầu/cuối.
- Issue không có assignee bị loại khỏi cả Room và các ô tổng quan.
- Quy trình của team bảo đảm mỗi issue chỉ có một assignee. Ứng dụng dùng assignee đầu tiên trong payload GitLab làm người xử lý hiện tại.
- Không phân biệt hoặc hiển thị role Dev, QC, Product.
- Chỉ hiển thị nhân viên đang có ít nhất một task hợp lệ.
- Mỗi nhân viên xuất hiện đúng một lần, kể cả khi có task ở nhiều label.
- Nếu một issue có nhiều workflow label, issue chỉ được tính một lần theo bước tiến xa nhất:
  `Todo < Doing < ToTest < Test < Passed`.
- Không áp dụng rule `updated_after` một tháng của màn hình GitLab Issues hiện tại. Dev Room phải tải đủ tất cả issue Open phù hợp bằng pagination.
- Dev Room tự refresh mỗi 2 phút khi màn hình đang hiển thị và vẫn có nút Refresh thủ công.
- Animation dùng hướng nhẹ, không thêm Lottie/Rive hoặc dependency mới.

## 3. Ngoài phạm vi

- Không sửa UI hoặc business rule của `GitLabDashboardView` và các tab GitLab hiện tại.
- Không kéo thả task giữa các bàn hoặc label.
- Không đổi assignee, label, state hay close issue từ OpsHub.
- Không lưu hoặc suy luận role của thành viên.
- Không hiển thị thành viên không có task.
- Không hiển thị issue chưa assign dưới dạng một bàn “Unassigned”.
- Không dùng webhook hoặc yêu cầu realtime tuyệt đối.
- Không lưu lịch sử người từng xử lý task.
- Không thêm cấu hình chọn Project trong phiên bản đầu.

## 4. Điều hướng và lifecycle

Thêm case `.devRoom` vào `AppSection` trong `ContentView.swift`.

Thứ tự menu:

1. Dashboard
2. Dev Room
3. Brew
4. GitLab
5. Settings

`ContentView` sở hữu `DevRoomViewModel` bằng `@StateObject`, tương tự cách đang giữ `GitLabDashboardViewModel`. Nhờ đó dữ liệu Dev Room được giữ trong bộ nhớ khi chuyển sang menu khác rồi quay lại.

Khi chọn Dev Room, phần detail hiển thị `DevRoomView`. Sidebar chính của OpsHub vẫn giữ đầy đủ các menu hiện có. Hình wireframe chỉ mô tả nội dung Dev Room, không yêu cầu xóa menu cũ.

## 5. Kiến trúc

### 5.1 Thành phần

```text
ContentView
  └─ DevRoomView
       ├─ DevRoomHeader
       ├─ DevRoomWorkflowSummary
       ├─ DevRoomEmployeeGrid
       │    └─ DevRoomEmployeeDesk
       └─ DevRoomEmployeeDetailPanel

DevRoomViewModel
  ├─ tải dữ liệu và quản lý cache trong phiên
  ├─ tổng hợp issue thành workflow summary + employee cards
  ├─ lọc theo workflow label
  └─ diff snapshot để phát animation event

DevRoomServicing
  └─ GitLabService
       └─ GitLab REST project issues endpoint + pagination
```

### 5.2 Boundary với GitLab hiện tại

Thêm protocol nhỏ `DevRoomServicing`, chỉ cung cấp dữ liệu mà Dev Room cần. `GitLabService` conform protocol này để dùng chung GitLab settings, HTTP client, REST decoding và `sendAllPages(...)`.

Không dùng trực tiếp `GitLabServicing.issues()` vì method đó hiện có các rule riêng:

- lấy workflow Project và `assigned_to_me` song song;
- trộn hai tập issue;
- giới hạn bằng `updated_after` một tháng;
- phục vụ các tab GitLab hiện tại.

Luồng mới phải dùng project issues endpoint riêng với:

- Project path `social/socom-issues`;
- `state=opened`;
- `order_by=updated_at`;
- `sort=desc`;
- `with_labels_details=true`;
- `per_page=100`;
- pagination theo `X-Next-Page`;
- không có `updated_after`;
- không có `scope=assigned_to_me`.

Tách Project path hiện tại thành constant `GitLabWorkflowProject.path` dùng chung cho request GitLab cũ và Dev Room. Thay đổi này chỉ loại bỏ literal trùng lặp; URL và behavior của request GitLab cũ phải giữ nguyên.

## 6. Mô hình dữ liệu

### 6.1 Workflow stage

`DevRoomWorkflowStage` là enum có thứ tự cố định:

| Stage | Label chuẩn hóa | Màu hiển thị |
|---|---|---|
| Todo | `todo` | Xám |
| Doing | `doing` | Xanh dương |
| ToTest | `totest` | Cam |
| Test | `test` | Tím |
| Passed | `passed` | Xanh lá |

Enum chịu trách nhiệm:

- normalize label;
- nhận diện workflow label;
- giải quyết issue có nhiều workflow label bằng stage có thứ tự cao nhất;
- cung cấp title, màu và thứ tự UI.

### 6.2 Issue và assignee

Dev Room dùng model riêng để không làm phình `GitLabIssue` đang phục vụ dashboard:

```swift
struct DevRoomIssue {
    let id: Int
    let iid: Int
    let title: String
    let webURL: URL?
    let updatedAt: Date?
    let stage: DevRoomWorkflowStage
    let assignee: DevRoomEmployee
}

struct DevRoomEmployee {
    let id: Int
    let name: String
    let username: String?
    let avatarURL: URL?
}
```

Group nhân viên bằng GitLab user `id`, không group bằng tên, để tránh trùng tên hoặc đổi display name.

### 6.3 Dữ liệu trình bày

`DevRoomEmployeeSummary` gồm:

- employee;
- toàn bộ task hợp lệ của người đó;
- tổng task;
- số task theo đủ năm stage;
- tối đa hai task cập nhật gần nhất để preview trên card.

Nhân viên được sắp xếp ổn định theo display name, sau đó theo GitLab user ID. Task trong card và detail được sắp xếp `updatedAt` giảm dần, fallback theo issue ID giảm dần.

## 7. Luồng tổng hợp

Sau khi service trả dữ liệu:

1. Giữ issue `opened` của Project cố định.
2. Normalize label và tìm stage tiến xa nhất.
3. Loại issue không có workflow stage.
4. Loại issue không có assignee.
5. Map assignee đầu tiên thành `DevRoomEmployee`.
6. Group issue theo employee ID.
7. Tạo năm workflow counts toàn Room.
8. Tạo card summary cho từng nhân viên.

Tổng của một workflow card phía trên phải bằng tổng count của stage tương ứng trên tất cả employee card. Tổng task của một nhân viên phải bằng tổng năm stage counts của người đó.

## 8. UI và tương tác

### 8.1 Header

Header nằm ngoài vùng scroll và gồm:

- title `Dev Room`;
- text Project cố định `social/socom-issues`;
- subtitle `Open issues có assignee`;
- thời gian cập nhật gần nhất;
- nút Refresh luôn nhìn thấy và bị disable khi đang tải.

Không có search box hoặc Project picker trong phiên bản đầu.

### 8.2 Workflow summary

Hiển thị năm card bằng nhau theo thứ tự `Todo`, `Doing`, `ToTest`, `Testing`, `Passed`.

Bấm một card sẽ lọc Room theo stage đó. Bấm lại card đang chọn sẽ bỏ lọc. Khi lọc:

- chỉ giữ nhân viên có ít nhất một task thuộc stage đã chọn;
- employee card vẫn hiển thị tổng workload và đủ năm counts để không mất bối cảnh;
- task preview ưu tiên các task thuộc stage đang lọc.

### 8.3 Employee grid

- Mỗi employee có một `DevRoomEmployeeDesk` duy nhất.
- Grid tự đổi số cột theo chiều rộng cửa sổ.
- Card phía trên bàn hiển thị avatar GitLab, tên, tổng task, tối đa hai task gần nhất và strip năm counts.
- Không hiển thị role hoặc một “trạng thái chính” cho nhân viên.
- Nhân vật dùng một bộ minh họa trung tính với vài biến thể màu/tóc xác định ổn định từ employee ID; danh tính thật vẫn dựa vào avatar và tên trên card.

### 8.4 Detail panel

Bấm employee card hoặc bàn sẽ mở panel bên phải:

- hiển thị avatar, tên và tổng task;
- group issue theo năm workflow stage;
- mỗi issue có `#iid`, title và thời điểm cập nhật;
- bấm issue mở `webURL` bằng trình duyệt mặc định;
- khi Room đang lọc theo stage, panel mở group đó trước nhưng vẫn cho xem các group còn lại.

Dev Room là read-only; panel không có control sửa GitLab.

## 9. Animation mức 1

### 9.1 Idle animation

`DevRoomCharacterView` dùng các layer SwiftUI nhẹ, không thêm dependency:

- tay gõ phím với biên độ nhỏ;
- chớp mắt ngắn;
- đầu hoặc thân chuyển động rất nhẹ;
- màn hình laptop đổi độ sáng nhẹ.

Nhịp animation được xác định từ employee ID để các nhân vật không chuyển động đồng thời. Không dùng animation liên tục có biên độ lớn, đi lại trong phòng hoặc hiệu ứng gây mất tập trung.

### 9.2 Task-change animation

`DevRoomViewModel` lưu snapshot thành công gần nhất theo issue ID với các field tối thiểu:

- assignee ID;
- workflow stage;
- title;
- updated timestamp.

Sau lần tải thành công tiếp theo, ViewModel diff snapshot cũ và mới:

| Thay đổi | Card bị tác động | Hiệu ứng |
|---|---|---|
| Issue mới | Assignee mới | Card/desk pulse nhẹ, count tăng |
| Đổi stage | Assignee hiện tại | Hai workflow count chuyển số, card pulse nhẹ |
| Đổi assignee | Người cũ và người mới | Card cũ giảm, card mới tăng |
| Issue bị close hoặc không còn hợp lệ | Assignee cũ | Count giảm; card biến mất nếu hết task |
| Chỉ đổi title | Assignee hiện tại | Cập nhật text, không pulse mạnh |

Lần tải thành công đầu tiên chỉ thiết lập baseline, không phát task-change animation. Refresh lỗi không thay snapshot và không phát animation sai.

### 9.3 Accessibility và hiệu năng

- Tôn trọng `accessibilityReduceMotion`: tắt idle loop và thay task-change animation bằng cập nhật tức thời hoặc fade ngắn.
- Auto refresh chạy trong SwiftUI `.task` nên tự hủy khi rời Dev Room.
- Idle animation dừng khi app/window không active.
- Chỉ card có thay đổi nhận event animation; không animate lại toàn bộ grid.
- Dùng transform/opacity nhẹ, tránh layout animation liên tục.

## 10. Refresh, cache và lỗi

`DevRoomViewModel` có vòng auto-refresh mặc định 2 phút, độc lập với chu kỳ 5 phút của `GitLabDashboardViewModel`.

- Lần mở Dev Room đầu tiên: tự tải dữ liệu.
- Quay lại Dev Room trong cùng phiên: hiển thị cache ngay; vòng 2 phút chỉ chạy khi view đang hiện.
- Refresh thủ công: tải mới bất kể đã có cache.
- Không cho hai request Dev Room chạy chồng nhau.
- Thành công: cập nhật Room, timestamp và snapshot.
- Lỗi khi đã có cache: giữ Room cũ, đánh dấu stale và hiển thị cảnh báo nhỏ.
- Lỗi khi chưa có cache: hiển thị error state với nút Retry.
- Không có issue phù hợp: hiển thị `Không có task đang mở trong Dev Room`.

Không persist snapshot xuống disk trong phiên bản đầu.

## 11. File boundary dự kiến

### File mới

- `Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift`
- `Sources/OpsHub/Features/DevRoom/Services/DevRoomServices.swift`
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift`
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomHeader.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDetailPanel.swift`
- `Tests/OpsHubTests/DevRoomAggregationTests.swift`
- `Tests/OpsHubTests/DevRoomServiceTests.swift`
- `Tests/OpsHubTests/DevRoomViewModelTests.swift`

### File sửa tối thiểu

- `Sources/OpsHub/App/ContentView.swift`: thêm menu, route và lifecycle owner cho Dev Room.
- `Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift`: cho `GitLabService` cung cấp project issue pagination cho `DevRoomServicing`, dùng lại REST helpers hiện có.

Không sửa `GitLabDashboardView`, `GitLabDashboardViewModel`, `GitLabIssueTab` hoặc UI các tab GitLab.

## 12. Test strategy

### 12.1 Pure aggregation tests

- Nhận diện đủ năm label, không phân biệt hoa thường và khoảng trắng.
- Loại issue không có workflow label.
- Loại issue không có assignee.
- Multiple workflow labels chọn stage tiến xa nhất.
- Một issue chỉ được tính một lần.
- Group theo employee ID và mỗi employee chỉ có một summary.
- Tổng toàn Room khớp tổng employee counts.
- Preview lấy đúng hai task mới nhất.
- Filter stage chỉ giữ employee phù hợp nhưng không làm mất full counts trên card.

### 12.2 Service tests

- Request dùng đúng project endpoint và `state=opened`.
- Request không có `updated_after` hoặc `scope=assigned_to_me`.
- Request bật `with_labels_details=true` và `per_page=100`.
- Theo hết `X-Next-Page`.
- Map đúng GitLab user ID, name, username, avatar và issue URL.
- Không làm thay đổi các test request hiện có của GitLab Issues.

### 12.3 ViewModel tests

- First load tạo baseline và không phát change event.
- Issue mới, đổi stage, đổi assignee và bị remove tác động đúng employee IDs/counts.
- Refresh lỗi giữ cache và snapshot cũ.
- Concurrent refresh chỉ tạo một request.
- Auto-refresh chạy theo interval inject được và dừng khi task bị cancel.
- Manual refresh luôn fetch lại.
- Reopen cùng phiên dùng cache.

### 12.4 Verification

- `swift test`
- `swift build`
- `swift build -c release`
- `git diff --check`
- Manual UI: sidebar cũ còn nguyên, Dev Room mở đúng screen, header cố định, grid responsive, filter/detail hoạt động, link mở GitLab, animation dừng với Reduce Motion và khi app inactive.

## 13. Acceptance criteria

1. OpsHub có menu Dev Room mới; các menu và màn hình hiện có giữ nguyên hành vi.
2. Dev Room chỉ dùng issue Open của `social/socom-issues` có workflow label và assignee.
3. Mỗi nhân viên có task xuất hiện đúng một lần; người không có task không xuất hiện.
4. Năm workflow totals và counts theo nhân viên chính xác, không double-count.
5. Issue nhiều workflow label được phân loại theo bước tiến xa nhất.
6. Có filter label, employee detail panel và link mở issue GitLab.
7. Tải đủ pagination và không áp dụng recency một tháng.
8. Auto-refresh 2 phút chỉ chạy khi Dev Room hiển thị; Refresh thủ công vẫn hoạt động.
9. Snapshot diff chỉ animate card bị thay đổi từ lần refresh thứ hai.
10. Idle animation nhẹ, tôn trọng Reduce Motion và dừng khi app/window inactive.
11. Lỗi refresh giữ cache; initial error và empty state có nội dung rõ ràng.
12. Không có mutation GitLab và không thay đổi behavior màn hình GitLab cũ.
