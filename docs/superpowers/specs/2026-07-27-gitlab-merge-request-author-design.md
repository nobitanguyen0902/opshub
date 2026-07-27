# GitLab Merge Request Author

## Mục tiêu

Hiển thị rõ người tạo merge request trên cả màn hình `Merge Requests` và `Reviews`, thay vì chỉ hiển thị avatar không có mô tả vai trò.

Mỗi row có author hợp lệ sẽ hiển thị avatar cùng nội dung:

```text
Requested by <tên người tạo>
```

Nếu GitLab không trả về author hoặc tên author rỗng, toàn bộ thông tin này được ẩn để tránh placeholder sai nghĩa.

## Phạm vi thay đổi

Giữ nguyên request tới GitLab và domain model hiện tại vì `GitLabService` đã ánh xạ `author.name` hoặc `author.username` sang `GitLabMergeRequest.authorName`, đồng thời đã lưu `authorAvatarURL`.

Mở rộng presentation dành cho work-item để giữ vai trò hiển thị của participant. Cả context `.mergeRequest` và `.review` đều ánh xạ author thành người request merge. Row dùng metadata này để render avatar và tên có nhãn rõ nghĩa.

Không thay đổi:

- GitLab API endpoint hoặc số lượng request.
- Filter participant hiện tại.
- Trạng thái, thao tác mở GitLab hoặc thứ tự danh sách.
- Cách hiển thị participant của Issue, Pipeline và Notification.

## Hiển thị

Trong layout rộng, `Requested by <tên>` nằm cùng vùng metadata với avatar và thời gian cập nhật. Trong layout hẹp, vùng này tiếp tục xuống hàng theo cấu trúc responsive hiện có.

Tên author giới hạn một dòng và được rút gọn khi không đủ chiều rộng. Accessibility summary tiếp tục chứa tên author; nhãn hiển thị giúp người dùng phân biệt author với assignee hoặc reviewer.

## Kiểm thử

Bổ sung regression test xác nhận:

- Merge Request presentation giữ author và gán vai trò `Requested by`.
- Review presentation sử dụng cùng vai trò `Requested by`.
- Author thiếu hoặc tên rỗng không tạo participant để UI không hiển thị thông tin rỗng.
- Các presentation khác không bị đổi vai trò hoặc hành vi ngoài phạm vi.

Sau khi triển khai, chạy:

```bash
swift test --filter GitLabWorkItemPresentationTests
swift test
swift build
swift build -c release
git diff --check
```
