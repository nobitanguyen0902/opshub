# GitLab Doing Issue Tab Design

## Mục tiêu

Bổ sung tab thứ sáu tên `Doing` vào danh sách GitLab Issues. Tab mới nằm ngay sau `Assign me` và hiển thị các issue thuộc workflow project có label `Doing`, đồng thời giữ nguyên giao diện, cách fetch API và hành vi của năm tab hiện tại.

## Phạm vi

- Thứ tự tab: `Assign me`, `Doing`, `Test`, `Passed`, `Build`, `Bug Pro`.
- Tab `Doing` chỉ nhận issue thuộc workflow project `social/socom-issues`.
- Issue phải có label `Doing`; việc so khớp không phân biệt chữ hoa, chữ thường và bỏ khoảng trắng thừa, theo convention hiện tại.
- Tab `Doing` không yêu cầu issue được assign cho người dùng hiện tại.
- Giữ nguyên điều kiện API hiện có: issue đang mở, cập nhật trong một tháng gần nhất, lấy đủ các trang dữ liệu và giữ label details.

## Thiết kế

Mở rộng `GitLabIssueTab` bằng case `doing` có tiêu đề `Doing`, đặt ngay sau `assignedToMe`. `GitLabIssuesView` đang render `GitLabIssueTab.allCases`, vì vậy tab mới tự xuất hiện đúng vị trí mà không cần thay đổi cấu trúc SwiftUI.

Rule lọc tiếp tục nằm trong `GitLabIssueTab.includes(_:)`. Case `doing` kiểm tra cả `issue.isWorkflowProject` và tập label đã được chuẩn hóa có chứa `doing`. Cách này giữ rule của toàn bộ workflow tabs tại một seam duy nhất và tái sử dụng dữ liệu issue đã fetch.

Không thêm request GitLab riêng cho label `Doing`, không thay đổi service, ViewModel, model dữ liệu issue hoặc component hiển thị danh sách.

## Luồng dữ liệu

1. Service tiếp tục fetch song song issue của workflow project và issue `assigned_to_me` theo cơ chế hiện tại.
2. Service phân trang, merge theo issue ID và gắn trạng thái `isWorkflowProject`/`isAssignedToMe` như hiện tại.
3. ViewModel tiếp tục lọc danh sách đã tải bằng tab đang chọn.
4. Khi chọn `Doing`, `GitLabIssueTab.includes(_:)` chỉ giữ issue của workflow project có label `Doing`.
5. View tiếp tục dùng cùng list, row, empty state và hành vi chọn issue hiện có.

## Xử lý lỗi và trạng thái rỗng

Tab `Doing` sử dụng nguyên load state, retry và partial-load behavior của Issues hiện tại. Nếu không có issue phù hợp, tab hiển thị empty state hiện có; không bổ sung thông báo hoặc nhánh lỗi riêng.

## Kiểm thử

Bổ sung các test method độc lập trong `GitLabIssueTabTests` để xác nhận:

- Issue thuộc workflow project có label `Doing` được hiển thị.
- Issue không có label `Doing` không được hiển thị.
- Label được so khớp không phân biệt chữ hoa, chữ thường và khoảng trắng thừa.
- Issue ngoài workflow project không được hiển thị dù có label `Doing`.
- Thứ tự `allCases` đặt `Doing` ngay sau `Assign me` để tránh regression vị trí tab.

Sau khi triển khai, chạy `swift test`, `swift build -c release` và `git diff --check`.

## Ngoài phạm vi

- Không thay đổi project scope hoặc giới hạn cập nhật một tháng.
- Không thay đổi cách gọi, phân trang hay merge GitLab API.
- Không thay đổi UI của các tab, issue row, label badge hoặc issue details.
- Không thay đổi rule của năm tab hiện tại.
