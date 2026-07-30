# Thiết kế Dashboard Assignee và Member Task Inspector

**Ngày:** 2026-07-30  
**Trạng thái:** Chờ duyệt  
**Phạm vi:** Bổ sung assignee cho danh sách production bug và xem nhanh task theo member trên Sprint Dashboard.

## 1. Mục tiêu

- Mỗi production bug cho biết ngay người đang được assign xử lý.
- Click một hàng trong `Member progress` mở danh sách sprint task của member đó mà không rời Dashboard.
- Giữ nguyên nguồn dữ liệu, quy tắc tính KPI, milestone và phong cách Flat + Terminal hiện tại.

## 2. Interaction đã chọn

Danh sách task dùng `Inspector panel` trượt vào từ cạnh phải của vùng Dashboard:

- panel rộng khoảng `460pt`, có thể thu hẹp theo chiều rộng cửa sổ;
- Dashboard vẫn hiện phía sau, không có scrim và không bị khóa thao tác;
- panel xuất hiện bằng transition từ cạnh phải trong khoảng 150–250ms;
- click member khác thay nội dung trên cùng inspector;
- đóng bằng nút `X` hoặc phím `Esc`;
- khi đóng, focus quay lại hàng member đã mở inspector.

Toàn bộ hàng member là một `Button`, có pressed/hover feedback và vùng click tối thiểu 44pt. Hàng `Unassigned` cũng mở inspector để rà các task chưa có owner.

## 3. Production bug assignee

Mỗi hàng production bug giữ nguyên hành vi click để mở GitLab và bổ sung ở vùng metadata bên phải:

- avatar 28pt của assignee hiện tại;
- fallback initials khi URL avatar thiếu hoặc tải lỗi;
- tooltip và accessibility label chứa display name;
- nếu chưa assign, dùng biểu tượng `person.crop.circle.badge.questionmark` và label `Unassigned`.

Avatar chỉ cung cấp ngữ cảnh, không tạo nested button và không có hành vi click riêng. Việc mở issue vẫn thuộc toàn bộ production bug row.

## 4. Nội dung Member Task Inspector

### Header

- avatar, display name và username;
- tổng số task;
- số và tỷ lệ task đã released;
- nút đóng có label và hint cho accessibility.

Với `Unassigned`, header dùng icon và copy rõ ràng `Unassigned` / `Needs an owner`.

### Danh sách task

Inspector hiển thị tất cả sprint issue thuộc đúng hàng member đang chọn. Mỗi task gồm:

- tiêu đề;
- `project #IID`;
- workflow label phù hợp nếu có;
- trạng thái released bằng text/icon, không chỉ dựa vào màu;
- thời điểm cập nhật tương đối nếu có;
- affordance mở liên kết GitLab.

Task có `webURL` là button mở GitLab. Task thiếu URL vẫn hiển thị nhưng ở trạng thái không tương tác và có accessibility hint giải thích link không khả dụng.

Danh sách sắp xếp theo `updatedAt` mới nhất trước; khi bằng nhau dùng GitLab global issue ID giảm dần để ổn định. Nếu dữ liệu của member rỗng do state thay đổi, inspector hiển thị empty state và có nút đóng thay vì vùng trắng.

## 5. Data flow

Không thêm API request. `sprintIssues` đã được tải để tính `Member progress`.

`SprintDashboardMemberSummary` được mở rộng để giữ danh sách issue đã dùng cho chính hàng đó:

```swift
struct SprintDashboardMemberSummary {
    let member: SprintDashboardMember?
    let issues: [SprintDashboardIssue]

    var ticketCount: Int { issues.count }
    var releasedCount: Int { issues.count(where: SprintDashboardAggregator.isReleased) }
}
```

Aggregator vẫn:

- chỉ tạo hàng cho configured members;
- giữ task chưa assign trong hàng `Unassigned`;
- không đưa task của member ngoài cấu hình vào inspector;
- dedupe issue trước khi grouping;
- dùng đúng assignee hiện tại đã map từ GitLab.

`DashboardView` giữ selection cục bộ bằng ID của member summary. Khi refresh hoặc đổi milestone làm selection không còn tồn tại, inspector tự đóng; nếu summary vẫn tồn tại, nội dung dùng dữ liệu mới.

## 6. Trạng thái và khả năng truy cập

- Inspector không mở trong khi Member progress chưa có dữ liệu.
- Refresh đang chạy vẫn giữ inspector nếu member tương ứng còn trong dữ liệu cũ; nội dung cập nhật sau khi refresh hoàn tất.
- Stale data tiếp tục hiển thị cùng warning hiện có.
- Member row có accessibility label gồm tên, số task, số released và hint `Shows this member's sprint tasks`.
- Inspector có heading rõ ràng, thứ tự focus từ header → close → task list.
- Avatar là decorative khi tên assignee đã được đọc trong row; không lặp thông tin cho VoiceOver.
- Light/dark mode dùng semantic token sẵn có; không thêm màu hardcode.

## 7. Kiểm thử

### Aggregation tests

- summary giữ đúng issue của configured member;
- `Unassigned` giữ đúng issue chưa có assignee;
- member ngoài cấu hình không xuất hiện và task của họ không lọt vào inspector;
- issue trùng global ID chỉ xuất hiện một lần với bản cập nhật mới hơn;
- task trong summary được sắp theo `updatedAt`, fallback global ID;
- `ticketCount`, `releasedCount` và `progress` vẫn giữ kết quả hiện tại.

### View model và build checks

- refresh/đổi milestone vẫn tạo presentation data đúng;
- `swift test --filter SprintDashboardAggregationTests`;
- `swift test --filter SprintDashboardViewModelTests`;
- `swift build`;
- `swift build -c release`;
- `git diff --check`.

## 8. Ngoài phạm vi

- Không thêm tìm kiếm, filter hoặc bulk action trong inspector.
- Không sửa assignee, label hoặc issue từ Dashboard.
- Không thay đổi query GitLab hay tạo endpoint mới.
- Không đổi KPI, release rule hoặc Dev Room member settings.
- Không refactor các màn hình GitLab/Dev Room khác.
