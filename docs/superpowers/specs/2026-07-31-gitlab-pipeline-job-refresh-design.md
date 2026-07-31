# GitLab Pipeline Job Refresh Design

## Mục tiêu

Sau khi người dùng bấm Build, trạng thái job/stage trong OpsHub phải tiếp tục đồng bộ với GitLab cho đến khi đạt trạng thái kết thúc. Nút Refresh chung cũng phải tải lại job details của các pipeline đã được mở, thay vì chỉ cập nhật pipeline summary.

## Các phương án

1. Chỉ kéo dài polling sau Build: cập nhật tự động tốt hơn nhưng Refresh chung vẫn giữ snapshot cũ.
2. Chỉ refresh job details khi bấm Refresh: patch nhỏ nhưng trạng thái sau Build không tự cập nhật.
3. Kết hợp polling có giới hạn và refresh details đã tải: bao phủ cả luồng tự động lẫn phục hồi thủ công, không tải jobs cho toàn bộ pipeline.

Chọn phương án 3.

## Thiết kế

- Stage action state chỉ khóa thao tác trong lúc xác minh jobs và gửi mutation lên GitLab. Sau khi GitLab chấp nhận mutation, action trở về idle để người dùng vẫn có thể Cancel một job đang chạy.
- Job status trả về từ mutation được ghi ngay vào details trước lượt poll đầu tiên, tránh khoảng trống mà UI vẫn hiển thị `Manual` và cho phép Build trùng.
- Mỗi stage có tối đa một monitoring task. Action mới trên cùng stage hủy task cũ và thay bằng task mới.
- Monitoring tải lại jobs ngay lập tức, sau đó tại các mốc 2, 5, 10 giây và mỗi 10 giây, tối đa 30 phút.
- Monitoring dừng khi stage đạt `success`, `failed` hoặc `canceled`; cập nhật notice tương ứng.
- Khi hết 30 phút mà stage vẫn active, giữ snapshot mới nhất và hiển thị notice trung tính rằng job vẫn đang chạy. Không báo thành công giả và không poll vô hạn.
- Refresh chung tiếp tục tải pipeline summaries như hiện tại, sau đó force-refresh job details cho các pipeline vẫn còn trong kết quả và đã có entry trong `pipelineDetails`.
- Pipeline chưa từng mở không bị gọi Jobs API. Lỗi refresh một pipeline detail giữ lại snapshot cũ và không làm hỏng toàn bộ dashboard refresh.
- Khi pipeline biến mất khỏi batch hiện tại, xóa cache/action state và hủy monitoring task tương ứng.

## Kiểm thử

- Regression test: Build được chấp nhận, job trả về `running` qua nhiều lượt poll rồi chuyển `success`; UI details phải thành `success`.
- Regression test: cache đang `running`, Refresh chung nhận job `success`; details phải được cập nhật.
- Kiểm tra action trở về idle sau khi mutation được chấp nhận, không bị khóa suốt vòng đời build.
- Giữ coverage hiện có cho tag/unknown pipeline read-only và mutation failure.

## Phạm vi

Thay đổi cục bộ trong `GitLabDashboardViewModel` và các test liên quan. Không thay API contract, service endpoint, UI layout, release workflow hoặc tạo mutation CI thật.
