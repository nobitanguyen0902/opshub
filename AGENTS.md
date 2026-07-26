# AGENTS.md

## Phạm vi và nguyên tắc làm việc

- Phản hồi bằng ngôn ngữ phù hợp với ngữ cảnh, ưu tiên tiếng Việt khi người dùng dùng tiếng Việt.
- Bám sát yêu cầu và phạm vi đã chốt; không tự ý refactor, đổi kiến trúc hoặc thay đổi hành vi không liên quan.
- Ưu tiên thay đổi nhỏ, cục bộ và nhất quán với convention Swift hiện có.
- Không chỉnh sửa hoặc xóa thay đổi sẵn có của người dùng nếu chưa được yêu cầu.
- Trước khi thay đổi contract, schema, dữ liệu hoặc workflow, đánh giá rõ khả năng tương thích ngược và tác động đến release.
- Không ghi hoặc commit secret, token, private key, certificate hay dữ liệu nhạy cảm.
- Không commit, push, mở PR hoặc gửi thông báo bên ngoài nếu người dùng chưa yêu cầu rõ.

## Cấu trúc project

- `Sources/OpsHub/App`: lifecycle và màn hình cấp ứng dụng.
- `Sources/OpsHub/Core`: các dịch vụ nền tảng như settings, shell và update.
- `Sources/OpsHub/Features`: các feature độc lập, hiện gồm Brew, DevRoom, GitLab và AppUpdate.
- `Sources/OpsHub/Shared`: component và tiện ích dùng chung.
- `Tests/OpsHubTests`: unit test cho các module của ứng dụng.
- `scripts/package-macos-app.sh`: đóng gói `.app` và `.zip` để phát hành.
- `Casks/opshub.rb`: Homebrew Cask trỏ tới GitHub Release mới nhất.

Khi sửa GitLab, giữ logic domain/filter gần model và service hiện có; kiểm tra các màn hình, view model, fixture và test liên quan. Khi sửa Brew hoặc packaging, tránh thay đổi side effect của lệnh shell, signing và release nếu không nằm trong yêu cầu.

## Build, test và kiểm tra

Chạy các lệnh từ root repository:

```bash
swift build
swift test
swift build -c release
git diff --check
```

Khi thay đổi có phạm vi hẹp, chạy thêm test filter tương ứng, ví dụ:

```bash
swift test --filter GitLabIssueTabTests
```

Chạy app local bằng:

```bash
swift run OpsHub
```

Chỉ chạy script packaging khi yêu cầu liên quan đến artifact phát hành; không tự tạo release, upload artifact hoặc thay đổi Homebrew Cask.

## Quy tắc code và test

- Tuân thủ Swift version, formatter/linter và pattern đang có trong repository.
- Ưu tiên abstraction/service hiện có thay vì dựng lại logic hoặc hardcode môi trường.
- Với bug có thể tái hiện, bổ sung regression test chứng minh hành vi trước khi sửa production code.
- Test tập trung vào hành vi, tránh phụ thuộc mạng, thời gian thực hoặc trạng thái bên ngoài khi không cần thiết.
- Khi đổi label, filter, route hoặc API GitLab, kiểm tra cả input chuẩn hóa, giá trị legacy, trạng thái không liên quan và UI consumer.
- Khi thay đổi asynchronous UI hoặc process shell, kiểm tra cancellation, lỗi, trạng thái loading và khả năng chạy lặp.
- Sau khi sửa, kiểm tra diff, phạm vi file thay đổi và các tác động phụ trước khi bàn giao.

## Bàn giao

Tóm tắt mục tiêu đã xử lý, file/khu vực bị ảnh hưởng, lệnh kiểm thử đã chạy và giới hạn còn lại. Nếu không thể chạy một kiểm tra, nêu rõ lý do và phần đã xác minh bằng cách khác.
