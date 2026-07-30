# Thiết kế Sprint Dashboard

**Ngày:** 2026-07-29
**Trạng thái:** Đã chốt
**Phạm vi:** Thay Dashboard placeholder bằng màn hình tổng hợp issue GitLab theo milestone sprint tuần.

## 1. Mục tiêu

Dashboard cho biết nhanh sức khỏe của sprint hiện tại:

- tổng ticket đã cam kết trong sprint;
- tổng ticket đã release;
- tổng production bug phát sinh trong khoảng thời gian sprint;
- phân bổ ticket và kết quả release theo thành viên đang xử lý.

GitLab là nguồn dữ liệu duy nhất. Dashboard chỉ đọc dữ liệu, không tạo milestone và không sửa issue, label hoặc assignee.

## 2. Quyết định đã chốt

- Sprint dùng GitLab milestone thay vì snapshot local hoặc lịch sử label.
- Team tạo một milestone cho mỗi sprint và gắn ticket đã cam kết vào milestone đó.
- Milestone có `start_date` là thứ Tư và `due_date` là thứ Ba tuần kế tiếp.
- GitLab milestone chỉ lưu ngày, vì vậy khoảng sprint được tính trọn ngày theo múi giờ `Asia/Ho_Chi_Minh`.
- `Sprint tickets` là tổng issue thuộc milestone đang chọn.
- `Released` là issue thuộc milestone và có đủ ba label `Passed`, `ToProduction`, `Merged`.
- So khớp label không phân biệt hoa thường và bỏ khoảng trắng đầu/cuối.
- `New production bugs` là issue có label `Bug Production` và `created_at` nằm trong khoảng ngày của sprint.
- Production bug không bắt buộc thuộc milestone và không phụ thuộc assignee.
- Bảng thành viên dùng assignee hiện tại của issue. Nếu assignee thay đổi thì số liệu theo thành viên cũng thay đổi.
- Theo convention hiện tại, ứng dụng dùng assignee đầu tiên trong payload GitLab.
- Issue không có assignee được gom vào hàng `Unassigned`.
- Hai cột `Tickets` và `Released`, gồm cả header và số liệu, được căn giữa.
- Giữ phong cách Flat + Terminal hiện tại của OpsHub và hỗ trợ cả light/dark appearance qua semantic theme token.

## 3. Ngoài phạm vi

- Không tự động tạo, đóng hoặc cập nhật milestone.
- Không tự gắn milestone cho issue.
- Không lưu snapshot sprint hoặc lịch sử assignee.
- Không đọc resource-label event để suy luận thời điểm đổi workflow.
- Không thay đổi logic hoặc UI của GitLab Overview, Issues, Merge Requests, Reviews và Pipelines.
- Không thay đổi workflow `Testing → Passed → ToProduction → Merged`.
- Không thêm chart lịch sử, so sánh nhiều sprint hoặc export dữ liệu trong phiên bản đầu.
- Không commit, push, release hoặc thay đổi Homebrew Cask trong phạm vi này.

## 4. Quy tắc phạm vi dữ liệu

### 4.1 Project

Dashboard dùng workflow Project hiện tại tại `GitLabWorkflowProject.path`. Không thêm Project picker trong phiên bản đầu.

### 4.2 Milestone đang chọn

Service tải milestone của workflow Project bằng request không giới hạn `state`, sắp xếp `due_date` giảm dần, đi hết pagination, sau đó giữ các milestone có đủ `start_date` và `due_date`.

Lần mở Dashboard đầu tiên:

1. Chọn milestone đang active mà ngày hiện tại nằm trong khoảng `start_date...due_date`.
2. Nếu không có milestone khớp, hiển thị trạng thái chưa có sprint hiện tại và cho phép chọn milestone khác.
3. Nếu có nhiều milestone cùng bao phủ ngày hiện tại, ưu tiên milestone có `start_date` gần ngày hiện tại nhất; nếu vẫn trùng, dùng GitLab milestone ID lớn hơn để có kết quả ổn định.

Milestone picker cho phép xem lại milestone đã tải. Thay đổi lựa chọn phải giữ cấu trúc màn hình và tải lại số liệu tương ứng.

### 4.3 Khoảng thời gian sprint

Từ milestone:

```text
start = start_date 00:00:00 Asia/Ho_Chi_Minh
end   = due_date   23:59:59.999 Asia/Ho_Chi_Minh
```

Production bug được tính khi `created_at >= start && created_at <= end`.

Không dùng thời điểm họp sáng thứ Tư hoặc thời điểm build chiều thứ Ba làm cutoff chính xác vì GitLab milestone không lưu giờ.

## 5. Quy tắc chỉ số

### 5.1 Sprint tickets

Tải tất cả issue của workflow Project bằng query `milestone=<milestone title>`, `state=all` và pagination đầy đủ.

`Sprint tickets` bằng số issue duy nhất thuộc tập này. Dedupe bằng GitLab global issue ID.

### 5.2 Released

Một sprint ticket được tính là released khi tập label chuẩn hóa chứa đủ:

```text
passed
toproduction
merged
```

Issue có thêm label khác vẫn hợp lệ. Issue thiếu một trong ba label không được tính released.

### 5.3 New production bugs

Tải issue của workflow Project có label `Bug Production`, `state=all`, `created_after=<sprint start>` và `created_before=<instant after sprint end>`. Hai thời điểm được đổi sang ISO-8601 UTC trước khi đưa vào request. Domain layer luôn lọc lại bằng `created_at` sau khi parse; kết quả client-side theo múi giờ Việt Nam là nguồn sự thật cho boundary.

Số bug:

- không lọc theo milestone;
- không lọc theo assignee;
- không thay đổi khi issue đổi người xử lý;
- vẫn được tính nếu issue đã close trong sprint.

Issue thiếu hoặc parse lỗi `created_at` không được tính và phải tạo warning dữ liệu thay vì suy đoán thời gian.

## 6. Bảng theo thành viên

Dashboard dùng danh sách thành viên đã chọn trong Dev Room settings để xác định các hàng chính.

Với mỗi sprint ticket:

1. Lấy assignee đầu tiên làm assignee hiện tại.
2. Nếu assignee thuộc danh sách thành viên đã chọn, cộng vào hàng tương ứng.
3. Nếu issue không có assignee, cộng vào `Unassigned`.
4. Nếu assignee không thuộc danh sách đã chọn, không hiển thị thành hàng riêng trong phiên bản đầu.

Để các KPI và bảng có ngữ nghĩa rõ:

- KPI `Sprint tickets` và `Released` luôn phản ánh toàn bộ milestone.
- Header bảng nói rõ đây là phần breakdown của các thành viên được cấu hình.
- Tổng các hàng trong bảng có thể nhỏ hơn KPI khi milestone có ticket thuộc người ngoài danh sách đã chọn.

Mỗi hàng gồm:

| Cột | Nội dung |
|---|---|
| Member | Avatar, display name và username nếu có |
| Tickets | Số sprint ticket đang assign |
| Released | Số ticket của hàng đó đạt release rule |
| Progress | `Released / Tickets`, hiển thị bằng progress bar |

Khi `Tickets = 0`, progress bằng `0` và không thực hiện phép chia.

Thứ tự:

1. thành viên được sắp xếp theo display name, fallback theo GitLab user ID;
2. `Unassigned` luôn nằm cuối và chỉ xuất hiện khi có ticket.

Nếu chưa cấu hình thành viên, Dashboard vẫn hiển thị ba KPI và production bug list, còn bảng hiển thị empty state dẫn người dùng tới Settings.

## 7. Kiến trúc

### 7.1 Thành phần

```text
ContentView
  └─ DashboardView
       ├─ SprintDashboardHeader
       ├─ SprintMetricGrid
       ├─ SprintMemberProgressTable
       └─ SprintProductionBugList

SprintDashboardViewModel
  ├─ milestone selection
  ├─ load/refresh lifecycle
  ├─ aggregate metrics
  ├─ member breakdown
  └─ stale/partial failure state

SprintDashboardServicing
  └─ GitLabService
       ├─ project milestones endpoint
       ├─ project issues by milestone endpoint
       └─ project issues by production-bug/date endpoint
```

### 7.2 Boundary với GitLab feature hiện tại

Không dùng `GitLabServicing.issues()` vì method đó:

- chỉ lấy issue `opened`;
- có `updated_after`;
- trộn workflow issue với `assigned_to_me`;
- phục vụ các tab GitLab hiện tại.

Thêm protocol nhỏ `SprintDashboardServicing` để Dashboard có query riêng nhưng vẫn tái sử dụng settings, request builder, REST decoding và `sendAllPages(...)` của `GitLabService`.

Query sprint ticket phải:

- scope đúng `GitLabWorkflowProject.path`;
- lọc bằng query `milestone=<milestone title>`;
- dùng `state=all`;
- có `with_labels_details=true`;
- có `per_page=100`;
- đi hết pagination;
- không có `scope=assigned_to_me`;
- không có `updated_after`.

Query production bug phải:

- scope cùng workflow Project;
- dùng `state=all`;
- lọc label `Bug Production`;
- truyền `created_after` và `created_before` theo khoảng ngày sprint;
- đi hết pagination;
- không lọc assignee hoặc milestone.

### 7.3 Mô hình domain

Không mở rộng `GitLabIssue` hiện tại bằng các field chỉ phục vụ Dashboard. Tạo model riêng, tối thiểu:

```swift
struct SprintMilestone {
    let id: Int
    let title: String
    let startDate: Date
    let dueDate: Date
}

struct SprintDashboardIssue {
    let id: Int
    let iid: Int
    let title: String
    let project: String
    let labels: [String]
    let assignee: SprintDashboardMember?
    let createdAt: Date?
    let updatedAt: Date?
    let webURL: URL?
}

struct SprintDashboardMemberSummary {
    let member: SprintDashboardMember
    let ticketCount: Int
    let releasedCount: Int
}
```

Aggregator là pure logic, nhận milestone, sprint issue, production bug và selected member IDs để tạo presentation data. Việc tách aggregator giúp kiểm thử boundary ngày, label và grouping mà không cần mạng hoặc SwiftUI.

### 7.4 Lifecycle

`ContentView` sở hữu `SprintDashboardViewModel` bằng `@StateObject` để giữ dữ liệu khi đổi menu.

Khi chọn Dashboard:

- lần đầu gọi `loadIfNeeded()`;
- có nút Refresh thủ công;
- tự refresh theo interval hiện có của GitLab dashboard là 5 phút;
- không chạy nhiều refresh đồng thời;
- đổi milestone hủy hoặc bỏ qua kết quả request cũ trước khi áp dụng request mới.

Khi Settings lưu danh sách thành viên Dev Room, `ContentView` truyền selected user IDs mới vào cả Dev Room và Sprint Dashboard để bảng cập nhật nhất quán.

## 8. UI đã duyệt

### 8.1 Header

Header dùng nền terminal tối thay vì vùng trắng độc lập và gồm:

- eyebrow `> OPSHUB / DASHBOARD`;
- title `Sprint health`;
- metadata milestone, date range và timezone;
- milestone picker;
- nút Refresh.

Header và nội dung dùng semantic token hiện có để appearance light/dark vẫn có contrast phù hợp; mockup tối không có nghĩa hardcode dark color trong production view.

### 8.2 KPI

Ba card bằng nhau trên một hàng:

1. `Sprint tickets`;
2. `Released`;
3. `New production bugs`.

Card bug dùng semantic warning accent và dấu cảnh báo; không dùng màu là tín hiệu duy nhất. Mỗi card có helper text ngắn mô tả rule, không có panel `Sprint scope`.

Ở chiều rộng hẹp, ba card chuyển thành một cột và không tạo horizontal scroll.

### 8.3 Team delivery

`Member progress` chiếm toàn chiều rộng dưới KPI.

- Member căn trái.
- `Tickets` và `Released` căn giữa cả header lẫn số.
- Số dùng tabular/monospaced figures.
- Progress bar không thay đổi layout khi giá trị cập nhật.
- Hàng có vùng tương tác tối thiểu 44pt nếu hỗ trợ click mở danh sách issue.

### 8.4 Production bug list

Danh sách nằm dưới bảng thành viên và hiển thị:

- indicator warning;
- title;
- Project + issue IID;
- thời gian tương đối;
- link mở issue GitLab.

List hiển thị tối đa 5 bug mới nhất theo `created_at` giảm dần. KPI vẫn đếm toàn bộ bug hợp lệ của sprint. Mỗi dòng mở issue tương ứng trên GitLab; phiên bản đầu không thêm một màn hình drill-down riêng.

## 9. Trạng thái tải và lỗi

### 9.1 Loading

- Lần tải đầu giữ sẵn kích thước khu vực KPI và bảng, hiển thị `ProgressView` hoặc skeleton nhẹ.
- Refresh giữ dữ liệu cũ trên màn hình và hiển thị trạng thái đang cập nhật; không thay bằng màn hình trắng.
- Nút Refresh bị disable trong lúc request đang chạy.

### 9.2 Empty

- Không có milestone hiện tại: giải thích rằng Project chưa có milestone bao phủ ngày hiện tại và cho chọn milestone khác.
- Milestone không có issue: KPI bằng `0`, bảng và list hiển thị empty state phù hợp.
- Không có production bug: card bằng `0`, list hiển thị trạng thái “No production bugs created in this sprint”.
- Chưa chọn thành viên: bảng hướng dẫn cấu hình member trong Settings nhưng KPI vẫn hoạt động.

### 9.3 Failure và stale data

Các request milestone, sprint issue và production bug có trạng thái lỗi rõ ràng.

- Nếu chưa có dữ liệu thành công, hiển thị lỗi cùng nút Retry.
- Nếu refresh lỗi sau khi đã có dữ liệu, giữ dữ liệu cũ và đánh dấu stale với message ngắn.
- Nếu sprint issue tải được nhưng production bug lỗi, vẫn hiển thị KPI và bảng milestone; card/list bug hiển thị lỗi cục bộ.
- Nếu production bug tải được nhưng sprint issue lỗi, vẫn hiển thị bug; KPI và bảng milestone hiển thị lỗi cục bộ.
- Không biến dữ liệu lỗi thành số `0`, vì `0` có nghĩa nghiệp vụ khác “không tải được”.

## 10. Accessibility và interaction

- Dùng SwiftUI semantic controls (`Button`, `Picker`, `ProgressView`) thay vì gesture trên container không có role.
- Mọi icon-only control có `accessibilityLabel`.
- VoiceOver đọc KPI theo dạng “Sprint tickets, 24”.
- Progress bar có accessibility value dạng “5 of 7 released, 71 percent”.
- Màu release và bug luôn đi cùng text/icon.
- Focus order theo thứ tự header → KPI → member table → bug list.
- Điều khiển bằng keyboard hoạt động và focus state nhìn thấy được.
- Dynamic Type không làm mất số hoặc cắt title quan trọng.
- Chuyển động chỉ dùng cho refresh/state transition ngắn và tôn trọng Reduce Motion.

## 11. Kiểm thử

### 11.1 Domain và aggregator

- Chọn đúng milestone chứa ngày hiện tại.
- Không chọn milestone ngoài khoảng ngày.
- Tie-break nhiều milestone ổn định.
- Boundary production bug tại đầu ngày thứ Tư và cuối ngày thứ Ba theo `Asia/Ho_Chi_Minh`.
- Loại bug trước/sau boundary và bug thiếu `created_at`.
- Bug không cần milestone và không phụ thuộc assignee.
- Release cần đủ `Passed`, `ToProduction`, `Merged`.
- Normalize label không phân biệt hoa thường và khoảng trắng.
- Dedupe issue theo global ID.
- Group theo assignee đầu tiên.
- `Unassigned` nằm cuối.
- Member ngoài selected IDs không tạo row.
- Progress bằng `0` khi không có ticket.

### 11.2 Service

- Milestone request dùng đúng workflow Project và pagination.
- Sprint issue request dùng milestone, `state=all`, label details và pagination.
- Production bug request dùng `Bug Production`, `state=all`, date filter và pagination.
- Không có `scope=assigned_to_me` hoặc `updated_after`.
- Decode milestone thiếu ngày mà không crash; domain bỏ milestone không đủ boundary.
- Map lỗi HTTP, authentication, cancellation và payload không hợp lệ theo convention hiện có.

### 11.3 ViewModel

- Load lần đầu, refresh, retry và auto-refresh.
- Không cho hai refresh chạy đồng thời.
- Đổi milestone không nhận kết quả stale của milestone cũ.
- Partial failure giữ phần dữ liệu tải thành công.
- Refresh failure giữ snapshot cũ.
- Thay đổi selected member IDs cập nhật bảng mà không cần tải lại dữ liệu GitLab.

### 11.4 UI

- Ba KPI cân bằng ở wide mode và xếp dọc ở narrow mode.
- Header không tạo mảng nền trắng lệch khỏi terminal surface.
- Hai cột `Tickets` và `Released` căn giữa.
- Loading, empty, failed, stale và partial state đều có nội dung rõ ràng.
- Light/dark appearance có contrast phù hợp.
- VoiceOver label, keyboard focus, Dynamic Type và Reduce Motion hoạt động.

## 12. Xác minh khi triển khai

Chạy từ repository root:

```bash
swift test --filter SprintDashboard
swift test
swift build
swift build -c release
git diff --check
```

Không chạy packaging script và không tạo release trong phạm vi này.

## 13. Điều hướng mặc định

- Mỗi lần ứng dụng khởi tạo một phiên chạy mới, mục được chọn mặc định là `Dashboard`.
- Không ghi nhớ hoặc khôi phục màn hình cuối cùng của phiên chạy trước.
- Sau khi mở ứng dụng, người dùng vẫn có thể chuyển sang các mục khác như hiện tại.
- Có regression test xác nhận `AppNavigationState` mới luôn khởi tạo với `.dashboard`.

## 14. Đồng bộ control milestone và refresh

- Chỉ thay đổi control chọn milestone và nút `Refresh` trong Dashboard header.
- Milestone và `Refresh` nằm trong một terminal control group duy nhất, dùng chung
  background, border, corner radius, font và chiều cao `42pt`.
- Milestone dùng `Picker` native kiểu menu đặt cạnh icon lịch và label
  `Milestone:` trong cùng segment. Picker tự render tên milestone đang chọn.
- Segment milestone rộng `300pt`.
- Khi chưa có milestone, hiển thị `No milestones` và disable riêng segment menu.
- Divider dọc phân tách Select và Button nhưng không tạo hai khung control rời nhau.
- Nút `Refresh` giữ icon và label trong mọi trạng thái; khi tải bổ sung spinner,
  disable riêng segment button và không làm thay đổi kích thước group.
- Dùng native `Picker` và `Button` semantics, accessibility label/value rõ ràng,
  không dùng tap gesture trên view không có role.
- Giữ nguyên vị trí header, nội dung tiêu đề, metadata, KPI và toàn bộ panel phía dưới.
- Giữ nguyên hành vi chọn milestone, refresh dữ liệu và accessibility label hiện có.
