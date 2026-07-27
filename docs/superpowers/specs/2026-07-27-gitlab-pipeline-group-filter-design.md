# GitLab Pipeline Group Filter

## Mục tiêu

Danh sách Pipeline chỉ tải dữ liệu từ các project thuộc một trong ba top-level group:

- `social`
- `Hara AI`
- `harasocial`

Project nằm trực tiếp trong group hoặc trong bất kỳ subgroup nào của ba group trên đều hợp lệ.

## Quy tắc lọc

Lấy segment đầu tiên trong `name_with_namespace` của project làm top-level group, loại bỏ khoảng trắng quanh segment rồi so sánh không phân biệt hoa thường với danh sách group được phép. Việc chuẩn hóa khoảng trắng hỗ trợ đúng display format của GitLab, ví dụ `social / project`.

Ví dụ:

- Nhận `social / project`.
- Nhận `social / backend / project`.
- Nhận `Hara AI / platform / project`.
- Nhận `harasocial / project`.
- Loại `social-tools / project`.
- Loại `other / social / project`.

Project thiếu `name_with_namespace` không được dùng để tải Pipeline vì không thể xác định group an toàn.

## Vị trí áp dụng

Áp dụng rule trong `GitLabService.pipelineBatch(scope:)` sau khi tải project catalog và kết hợp với project scope hiện tại, trước giới hạn số project và trước khi tạo request lấy Pipeline cho từng project.

Các danh sách GitLab khác tiếp tục dùng toàn bộ project catalog; rule mới chỉ ảnh hưởng dữ liệu Pipeline và các UI consumer dùng chung tập Pipeline đó, bao gồm preview và số lượng failed pipelines.

## Kiểm thử

Bổ sung regression test ở `GitLabServiceTests` với catalog gồm:

- Project trực tiếp trong group hợp lệ.
- Project thuộc subgroup của group hợp lệ.
- Project thuộc group có tên gần giống nhưng không hợp lệ.
- Project thuộc group không liên quan.

Test xác nhận chỉ project hợp lệ phát sinh request Pipeline và kết quả không chứa Pipeline từ project bị loại. Các test Pipeline hiện có được cập nhật fixture để dùng group hợp lệ, không thay đổi expectation ngoài rule mới.
