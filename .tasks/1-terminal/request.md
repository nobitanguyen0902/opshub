# User Request

## Feature

Cho phép đổi tên tab của Terminal trên macOS.

## Background

Hiện tại khi mở nhiều phiên Terminal để chạy các profile Hermes (Architect, Developer, Reviewer), rất khó phân biệt từng tab vì tất cả đều sử dụng tên mặc định của Terminal.

## Requirements

### 1. Đổi tên thủ công

Người dùng có thể đặt tên tùy ý cho tab Terminal đang mở.

Ví dụ:

* Architect
* Developer
* Reviewer
* Build
* Kafka Worker

Tên được cập nhật ngay sau khi người dùng xác nhận.

---

### 2. Đặt tên tự động

Khi mở một Terminal mới, hệ thống tự động đặt tên tab.

Mục tiêu là giúp người dùng dễ nhận biết tab ngay từ khi được tạo mà không cần thao tác thêm.

Tên tự động có thể dựa trên ngữ cảnh hiện tại (ví dụ: profile hoặc workspace nếu xác định được).

---

### 3. Hỗ trợ đồng thời hai chế độ

* Người dùng có thể để hệ thống đặt tên tự động.
* Người dùng cũng có thể đổi lại tên thủ công bất kỳ lúc nào.

Việc đổi tên thủ công sẽ ưu tiên hơn tên tự động.

## Scope

* Chỉ áp dụng cho **macOS Terminal**.
* Chỉ thay đổi tiêu đề (tab title/window title), không ảnh hưởng đến hoạt động của terminal.
* Không thay đổi hành vi của Hermes hoặc các profile.

## Acceptance Criteria

* Mở Terminal mới sẽ tự động có tên phù hợp.
* Người dùng có thể đổi tên tab bất kỳ lúc nào.
* Sau khi đổi tên thủ công, tên hiển thị đúng trên tab Terminal.
* Không ảnh hưởng tới việc chạy lệnh hoặc session hiện có.
* Tính năng hoạt động ổn định khi mở nhiều tab cùng lúc.

## Out of Scope

* Hỗ trợ iTerm2.
* Hỗ trợ Windows Terminal.
* Đồng bộ tên tab giữa các thiết bị.
