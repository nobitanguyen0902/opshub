# Task 7 report: Nhân vật và animation mức 1

## Kết quả

- Đã thay laptop placeholder bằng `DevRoomCharacterView` dựng hoàn toàn từ SwiftUI layers và SF Symbol, không thêm dependency hoặc asset.
- Idle typing/blink dùng delay và chu kỳ xác định theo employee ID để các nhân vật lệch nhịp ổn định.
- Idle task chỉ chạy khi Dev Room còn hiển thị, cửa sổ ở trạng thái `.key` và Reduce Motion tắt; SwiftUI hủy task khi view biến mất hoặc key thay đổi.
- Employee desk chỉ pulse khi generation thay đổi và employee ID thuộc event; task pulse cũ được cancel/reset khi có event mới, mất active, bật Reduce Motion hoặc view biến mất.
- `DevRoomView` relay event qua screen state sau khi generation đổi để employee mới được insert cùng refresh vẫn nhận pulse, nhưng first load/event cũ khi quay lại màn hình không bị phát lại.
- Workflow summary và năm stage count trên employee card dùng numeric transition; Reduce Motion giữ cập nhật số tức thời nhưng bỏ animation.
- Không thay đổi các màn hình GitLab/Brew cũ, service, ViewModel, dependency hoặc asset.

## Files

- `Sources/OpsHub/Features/DevRoom/Components/DevRoomCharacterView.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomEmployeeDesk.swift`
- `Sources/OpsHub/Features/DevRoom/Components/DevRoomWorkflowSummary.swift`
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift`

## Compile và test evidence

- `swift build`: pass, debug build hoàn tất không warning/error.
- `swift build -c release`: pass, production build hoàn tất không warning/error.
- `swift test`: pass `102/102`, không failure hoặc unexpected failure.
- `git diff --check`: pass, không có whitespace error.
- Existing `DevRoomSnapshotDifferTests` và `DevRoomViewModelTests` tiếp tục cover added/stage/reassign/remove affected IDs, unchanged/title-only suppression và first-load suppression; Task 7 chỉ thêm SwiftUI presentation/cancellation wiring nên không thêm UI test target mới.

## Manual UI evidence

- Không chạy `swift run OpsHub`: môi trường hiện tại không có cách quan sát/click GUI an toàn, trong khi process app sẽ tiếp tục chạy nếu không can thiệp.
- Không để process GUI chạy nền. Visual timing, click interaction và Reduce Motion system toggle chưa được xác nhận thủ công; debug/release compile xác nhận view tree và macOS 14 API hợp lệ.

## Self-review

- `controlActiveState == .key` compile trực tiếp với deployment target macOS 14; không cần fallback/deviation API.
- Animation liên tục chỉ thay đổi rotation của tay và kích thước mắt trong local character layer; grid/layout không dùng animation loop.
- Pulse dùng generation relay để tránh bỏ lỡ employee mới, guard đúng `employeeIDs`, và không chạy khi window inactive hoặc Reduce Motion bật.
- Numeric transition chỉ gắn vào từng count, không animate lại toàn grid.
- Scope code diff chỉ có đúng bốn file Dev Room trong brief; không phát hiện actionable issue sau self-review.

## Concerns / deviations

- Không có deviation về API hoặc kiến trúc.
- Concern duy nhất là chưa có manual GUI verification do giới hạn quan sát GUI nêu trên.
