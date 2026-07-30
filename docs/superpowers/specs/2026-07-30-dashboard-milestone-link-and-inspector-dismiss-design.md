# Dashboard Milestone Link and Inspector Dismiss Design

## Mục tiêu

- Cho phép mở trang chi tiết của milestone đang chọn từ Dashboard.
- Cho phép đóng nhanh Drawer Member Progress bằng cách bấm ngoài Drawer, bên cạnh nút đóng và phím Escape hiện có.

## Thiết kế

### Liên kết milestone

`SprintMilestone` nhận thêm `webURL` tùy chọn, được ánh xạ trực tiếp từ trường `web_url` của GitLab Milestones API. Dashboard hiển thị một nút external-link cạnh Milestone Picker:

- Mở `webURL` của milestone đang chọn bằng `openURL`.
- Disabled khi chưa chọn milestone hoặc API không trả `web_url`.
- Có accessibility label và hint mô tả hành vi mở GitLab.
- Không tự dựng URL từ host hoặc project path.

### Đóng nhanh Member Progress Drawer

Khi Drawer đang mở, Dashboard đặt một backdrop trong suốt phủ phần còn lại của màn hình:

- Bấm backdrop sẽ xóa member đang chọn và đóng Drawer.
- Drawer nằm trên backdrop nên thao tác bên trong Drawer không làm đóng Drawer.
- Nút X và phím Escape tiếp tục hoạt động.
- Không thay đổi nội dung, kích thước hoặc animation hiện có của Drawer.

## Tương thích và trạng thái lỗi

- Milestone không có `web_url` vẫn được tải và chọn như hiện tại; chỉ nút mở GitLab bị vô hiệu hóa.
- Không thay đổi API request, bộ lọc milestone, logic aggregation hoặc auto-refresh.
- Khi member không còn nằm trong dữ liệu đang hiển thị, hành vi tự đóng hiện tại được giữ nguyên.

## Kiểm thử

- Cập nhật test GitLab service để xác nhận `web_url` được ánh xạ vào `SprintMilestone`.
- Thêm test cho trạng thái có/không có link của milestone nếu logic presentation được tách riêng.
- Thêm regression test cho action đóng nhanh Drawer.
- Chạy focused tests cho Dashboard và GitLab service, sau đó `swift test`, `swift build`, `swift build -c release` và `git diff --check`.

## Ngoài phạm vi

- Không redesign Header, Milestone Picker hoặc Drawer.
- Không thêm điều hướng GitLab nội bộ.
- Không thay đổi hành vi mở issue trong Drawer.
