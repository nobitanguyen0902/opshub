# Dev Room Testing Label Fix

## Mục tiêu

Sửa workflow stage thứ tư của Dev Room để dùng đúng GitLab label `Testing` thay cho label sai `Test`.

## Phạm vi thay đổi

- Đổi enum `DevRoomWorkflowStage.test` thành `DevRoomWorkflowStage.testing`.
- Đổi tiêu đề hiển thị của stage thành `Testing`.
- `DevRoomWorkflowStage.stage(for:)` nhận label `Testing` theo cách không phân biệt hoa thường và bỏ khoảng trắng như các stage hiện có.
- Label cũ `Test` không còn được nhận là workflow stage, nên issue chỉ có label này không được tính vào Dev Room, danh sách nhân viên hoặc workflow totals.
- Giữ nguyên thứ tự workflow: `Todo` → `Doing` → `ToTest` → `Testing` → `Passed`.
- Đồng bộ tab GitLab testing đang có sang tiêu đề `Testing`; rule hiện tại nhận `Testing` hoặc `ToTest` vẫn giữ nguyên.
- Đổi toàn bộ source/test reference từ `.test` sang `.testing` và fixture workflow từ `Test` sang `Testing`.

## Không thay đổi

- Project vẫn cố định là `social/socom-issues`.
- Chỉ lấy issue đang mở và có assignee hiện tại.
- Không đổi màu stage, allowlist thành viên, drawer, animation hoặc layout Dev Room.
- Không thêm compatibility fallback cho label `Test`.

## Kiểm thử

- `Testing` được map thành `.testing` sau normalize case/whitespace.
- `Test` trả về `nil` nếu không có workflow label hợp lệ khác.
- Khi nhiều workflow labels cùng tồn tại, `Testing` vẫn đứng sau `ToTest` và trước `Passed`.
- Aggregation, filter, counts, representative stage và drawer grouping đều dùng `.testing`.
- GitLab testing tab hiển thị `Testing` và tiếp tục nhận issue có `Testing` hoặc `ToTest`.
- Chạy focused Dev Room/GitLab issue tab tests, full `swift test`, Release build và `git diff --check`.
