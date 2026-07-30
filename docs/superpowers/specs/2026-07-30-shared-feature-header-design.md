# Shared Feature Header Design

## Mục tiêu

Đồng bộ header của Dashboard, Brew, GitLab, Dev Room và Settings theo cùng một
ngôn ngữ giao diện Flat + Terminal-inspired. Dashboard hiện tại là source of
truth. Toàn bộ hành vi nghiệp vụ, trạng thái và action của từng feature phải
được giữ nguyên.

## Phạm vi

- Tạo một header dùng chung trong `Sources/OpsHub/Shared/Components`.
- Áp dụng header dùng chung cho Dashboard, Brew, GitLab, Dev Room và Settings.
- Cho phép sắp xếp lại control trong vùng header để phù hợp với chiều rộng và
  mật độ nội dung của từng feature.
- Không thay đổi ViewModel, service, API, navigation, keyboard shortcut hoặc
  workflow của bất kỳ feature nào.
- Không thay đổi nội dung bên dưới header ngoài phần spacing cần thiết để giữ
  nhịp layout nhất quán.

## Cấu trúc component

`OpsHubFeatureHeader` là component trình bày dùng chung với các đầu vào:

- `eyebrow`: định danh dạng `OPSHUB / FEATURE`.
- `title`: tiêu đề chính của màn hình.
- `metadata`: nội dung phụ dạng monospaced caption.
- `controls`: view slot tùy chọn cho control đặc thù.
- `status`: view slot tùy chọn cho cảnh báo hoặc trạng thái liên quan trực tiếp
  đến header.
- `layout`: cho phép control nằm bên phải ở chiều rộng phù hợp hoặc xuống hàng
  trong màn hình hẹp.

Component sở hữu typography, spacing, border, surface và accessibility
grouping. Feature sở hữu dữ liệu, binding, action, loading và disabled state.
Nhờ vậy việc đổi style không kéo logic feature vào shared component.

## Hierarchy và layout

Header dùng cùng hierarchy với Dashboard:

1. Dòng định danh nhỏ: dấu `>` màu accent và `OPSHUB / FEATURE`.
2. Tiêu đề chính 26pt, bold, monospaced.
3. Metadata caption có màu secondary.
4. Controls được gom thành một nhóm terminal control ở bên phải.
5. Status liên quan trực tiếp đến header nằm thành hàng riêng bên dưới.

Toàn bộ header được đặt trong terminal surface có emphasized border và padding
16pt. Khoảng cách tuân theo nhịp 4/8pt hiện có. Khi không đủ chiều rộng,
title block nằm trên và controls nằm dưới để tránh cắt chữ hoặc ép nhỏ touch
target.

## Áp dụng theo feature

### Dashboard

Giữ nguyên nội dung `OPSHUB / DASHBOARD`, `Sprint health`, metadata milestone,
milestone picker, Refresh và banner stale/error. Chỉ chuyển phần trình bày vào
component dùng chung.

### Brew

Dùng `OPSHUB / BREW`, tiêu đề `Package manager` và metadata Homebrew hiện tại.
Giữ nguyên Refresh, Check Outdated, Update All, keyboard shortcut, confirmation
và disabled/loading state. Ba action được đặt trong control slot.

### GitLab

Dùng `OPSHUB / GITLAB`, tiêu đề `Workspace` và metadata scope/update/stale.
Giữ nguyên Search, project selector và Refresh. Layout vẫn thích ứng với
`GitLabWorkspaceLayoutMode`; narrow mode đặt controls xuống hàng. Cảnh báo tải
section vẫn nằm ở content vì không phải trạng thái riêng của header.

### Dev Room

Dùng `OPSHUB / DEV ROOM`, tiêu đề `Team workspace` và metadata project/source,
thời gian cập nhật và stale. Giữ nguyên Refresh cùng trạng thái loading. Các
thông tin cập nhật được gom vào metadata/status thay vì đứng rời ở mép phải.

### Settings

Dùng `OPSHUB / SETTINGS`, tiêu đề `Preferences` và mô tả cấu hình hiện tại.
Không có control slot. Các nút Save và Test Connection vẫn nằm trong nội dung
form để giữ đúng quan hệ với dữ liệu được chỉnh sửa.

## Accessibility

- Header được nhóm bằng `.accessibilityElement(children: .contain)`.
- Button và input tiếp tục dùng semantic SwiftUI controls.
- Giữ nguyên accessibility label, value và hint hiện có.
- Controls không nhỏ hơn kích thước hiện tại; Refresh của Dashboard tiếp tục có
  vùng tương tác tối thiểu 42pt.
- Không dùng màu làm tín hiệu duy nhất: stale/error vẫn có text và system image.
- Layout phải cho phép metadata và title hiển thị hợp lý khi tăng cỡ chữ.

## Trạng thái và lỗi

Shared component không xử lý async hay lỗi. Mỗi feature tiếp tục quyết định:

- khi nào action bị disabled;
- khi nào hiển thị spinner;
- nội dung stale/error;
- retry hoặc refresh action.

Việc tách này bảo đảm thay đổi giao diện không thay đổi data flow hiện tại.

## Kiểm thử và xác minh

- Build debug để bắt lỗi generic/view-builder của component.
- Chạy toàn bộ unit test để xác nhận ViewModel và business behavior không đổi.
- Build release để kiểm tra strict concurrency và cấu hình production.
- Chạy `git diff --check`.
- Rà soát SwiftUI previews hoặc chạy app ở light/dark mode, kiểm tra header của
  cả năm feature ở chiều rộng thường và hẹp.
- Kiểm tra Refresh/loading/disabled state, GitLab search/project selector, Brew
  confirmation và Dashboard milestone picker sau khi đổi layout.

## Tiêu chí hoàn tất

- Năm feature có cùng surface, hierarchy, typography, spacing và control-group
  treatment ở header.
- Không mất action, state, shortcut hoặc thông tin metadata hiện có.
- Header không bị tràn hoặc cắt control ở chiều rộng hẹp.
- Không có thay đổi ngoài phạm vi header và spacing trực tiếp liên quan.
