# Kanban SQLite WAL Read Fix

## Vấn đề

OpsHub mở `~/.hermes/kanban.db` bằng `SQLITE_OPEN_READONLY`. Database của Hermes dùng WAL; khi các file sidecar `kanban.db-wal` và `kanban.db-shm` chưa tồn tại, SQLite mở được file chính nhưng thất bại ở truy vấn đầu tiên với mã `SQLITE_CANTOPEN` và thông báo `unable to open database file`.

## Thay đổi

- Mở database bằng `SQLITE_OPEN_READWRITE` để SQLite có thể khởi tạo các file WAL/SHM cần thiết.
- Giữ `KanbanSQLiteReader` ở chế độ đọc về mặt nghiệp vụ: chỉ thực thi `SELECT` và `PRAGMA table_info`; không thêm câu lệnh ghi dữ liệu.
- Giữ nguyên đường dẫn database, schema, model, UI và thông báo lỗi hiện có.

## Kiểm thử

Thêm regression test tạo database ở journal mode WAL, tạo bảng và dữ liệu mẫu, đóng kết nối sạch, xóa sidecar để mô phỏng trạng thái database thực tế, rồi xác nhận `KanbanSQLiteReader` tải được task. Test hiện có cho đường dẫn, lỗi mở file, thứ tự task và schema không tương thích tiếp tục phải đạt.

## Tương thích và rủi ro

- Yêu cầu user chạy OpsHub có quyền ghi vào file database và thư mục `~/.hermes`; đây là thư mục dữ liệu thuộc user hiện tại.
- SQLite có thể tạo hoặc quản lý file WAL/SHM, nhưng OpsHub không thay đổi bản ghi Kanban.
- Không dùng `immutable=1` vì database có thể được Hermes cập nhật đồng thời; giả định immutable có nguy cơ trả dữ liệu cũ.
