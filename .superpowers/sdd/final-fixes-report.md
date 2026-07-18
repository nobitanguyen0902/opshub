# Final fixes report

## Kết quả

- `DevRoomAggregator` dedupe `DevRoomSourceIssue` theo issue ID trước khi normalize, filter và group.
- Khi GitLab trả trùng issue ID, aggregator chọn bản ghi có `updatedAt` mới hơn, phù hợp request ordering `updated_at desc`; nếu timestamp bằng nhau thì giữ bản ghi xuất hiện trước trong response.
- Mỗi issue chỉ còn được tính một lần trong room totals, employee totals và snapshot, nên `DevRoomSnapshot` không còn gặp duplicate-key trap.
- `DevRoomView` giữ message `Không có task đang mở trong Dev Room` khi room thật sự không có task.
- Khi room có task nhưng stage đang chọn không có employee, empty state hiển thị `Không có nhân viên ở bước <Stage>`.

## Regression coverage

- Aggregation tests xác nhận duplicate issue ID chỉ được tính một lần, bản ghi mới nhất quyết định assignee/stage/totals và response order là tie-break khi timestamp bằng nhau.
- ViewModel test chạy hai refresh có duplicate issue ID, xác nhận snapshot tạo an toàn, room vẫn có một issue và animation diff chỉ đánh dấu assignee cũ/mới của bản ghi được chọn.
- Empty-state là nhánh render nhỏ, dùng trực tiếp state đã có (`data.total`, `selectedStage`, `displayedEmployees`); không thêm UI-test infrastructure mới chỉ để kiểm tra copy.

## Verification

- `swift test --filter DevRoom`: 27/27 pass.
- `swift test`: 106/106 pass.
- `swift build -c debug`: pass.
- `swift build -c release`: pass.
- `git diff --check`: pass.

## Scope

- Chỉ sửa aggregation, Dev Room empty-state và regression tests liên quan.
- Không thay đổi service contract, GitLab request, kiến trúc hoặc dependency.
- Không commit thay đổi.
