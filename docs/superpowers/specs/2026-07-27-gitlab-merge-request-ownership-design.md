# GitLab Merge Request Ownership and Participants

## Mục tiêu

Màn hình `Merge Requests` phải hiển thị cả merge request đang assign cho người dùng và merge request do chính người dùng tạo. Vì vậy, merge request do người dùng tạo nhưng assign cho người khác vẫn xuất hiện trong danh sách.

Đồng thời, phân biệt rõ người tạo và người được assign trên cả màn hình `Merge Requests` và `Reviews`:

- Avatar người tạo nằm ngay cạnh tên project.
- Vùng participant cũ, trước timestamp, hiển thị avatar của assignee đầu tiên.

Nếu GitLab không trả về author hoặc assignee tương ứng, phần avatar đó được ẩn để tránh placeholder sai nghĩa.

## Nguồn dữ liệu Merge Requests

`GitLabService.mergeRequests()` tải song song hai tập merge request đang mở:

- `scope=assigned_to_me`: merge request đang assign cho người dùng.
- `scope=created_by_me`: merge request do người dùng tạo.

Hai kết quả được hợp nhất và chống trùng theo global merge request `id`. Danh sách cuối cùng được sắp xếp theo `updatedAt` giảm dần để giữ thứ tự ổn định, không phụ thuộc request nào hoàn thành trước.

Nếu một trong hai request lỗi, toàn bộ lần tải `Merge Requests` được coi là lỗi. Cơ chế partial-load hiện có của dashboard tiếp tục giữ dữ liệu cũ và hiển thị cảnh báo, tránh trình bày danh sách mới nhưng không đầy đủ như thể đã tải thành công.

`Reviews` tiếp tục dùng riêng `scope=reviews_for_me`; không hợp nhất với hai tập trên.

## Thông tin author và assignee

`GitLabService` tiếp tục ánh xạ `author.name` hoặc `author.username` sang `GitLabMergeRequest.authorName`, đồng thời giữ `authorAvatarURL`.

Domain model `GitLabMergeRequest` được bổ sung `assigneeName` và `assigneeAvatarURL`. Service chỉ ánh xạ phần tử đầu tiên của `GitLabRESTMergeRequest.assignees`; các assignee tiếp theo không được hiển thị theo phạm vi đã chốt.

Presentation tách riêng:

- `author`: dùng cho avatar cạnh project.
- `participants`: chứa tối đa một assignee và tiếp tục được render tại vùng participant cũ.

Cả context `.mergeRequest` và `.review` dùng cùng mapping này.

Không thay đổi:

- GitLab API endpoint; số request của `Merge Requests` tăng từ một lên hai trong mỗi lần tải.
- Filter participant hiện tại.
- Trạng thái, thao tác mở GitLab hoặc thứ tự danh sách.
- Cách hiển thị participant của Issue, Pipeline và Notification.

## Hiển thị

Tên project được đặt trong một `HStack` cùng avatar author. Avatar dùng component/avatar style hiện có và có tooltip/accessibility chứa tên author; không hiển thị thêm text `Requested by`.

Vùng participant trước timestamp chỉ hiển thị avatar assignee đầu tiên. Tooltip/accessibility chứa tên assignee. Trong layout hẹp, hai vùng giữ nguyên cấu trúc responsive hiện có.

Accessibility summary chứa cả author và assignee khi có dữ liệu, với vai trò rõ ràng để không bị hiểu nhầm.

## Kiểm thử

Bổ sung regression test xác nhận:

- Merge Requests gửi cả `scope=assigned_to_me` và `scope=created_by_me`.
- Merge request chỉ thuộc tập `created_by_me` vẫn xuất hiện.
- Merge request thuộc cả hai tập chỉ xuất hiện một lần.
- Kết quả hợp nhất được sắp xếp theo thời gian cập nhật giảm dần.
- Một trong hai request lỗi làm lần tải Merge Requests thất bại thay vì trả dữ liệu thiếu.
- Service ánh xạ author và chỉ assignee đầu tiên vào domain model.
- Merge Request và Review presentation giữ author riêng, đồng thời dùng assignee đầu tiên làm participant.
- Author thiếu hoặc tên rỗng không tạo author presentation.
- Assignee thiếu hoặc tên rỗng không tạo participant.
- Accessibility summary phân biệt author và assignee.
- Các presentation khác không bị đổi vai trò hoặc hành vi ngoài phạm vi.

Sau khi triển khai, chạy:

```bash
swift test --filter GitLabServiceTests
swift test --filter GitLabWorkItemPresentationTests
swift test
swift build
swift build -c release
git diff --check
```
