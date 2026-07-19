# Thiết kế lại giao diện Dev Room

**Ngày:** 2026-07-19  
**Trạng thái:** Chờ user review  
**Phạm vi:** Thay đổi phần trình bày Dev Room và bổ sung cấu hình chọn thành viên Dev Room trong Settings.

## 1. Mục tiêu

Dev Room phải tạo cảm giác như một căn phòng làm việc chung có nhiều nhân viên đang ngồi tại bàn và gõ phím. Giao diện không còn là danh sách card task tách rời khỏi các nhân vật hình học.

Thiết kế mới giữ nguyên nguồn GitLab issues, workflow, filter, refresh, snapshot diff và business rule đã chốt trong `2026-07-18-dev-room-design.md`. Project Members API chỉ được bổ sung để cấu hình allowlist.

Dev Room chỉ hiển thị và tính task của các GitLab user được chọn trong Settings. Đây là allowlist: thành viên mới mặc định không xuất hiện cho tới khi được chọn và lưu.

## 2. Nguyên tắc visual

- Tất cả nhân viên cùng nằm trong một không gian văn phòng liên tục.
- Không đặt mỗi nhân viên trong một card lớn độc lập.
- Nhân vật là Flat Chibi: đầu lớn, biểu cảm rõ, màu phẳng và dựng bằng SwiftUI.
- Bàn, laptop, ghế và nhân vật tạo thành một workstation thống nhất.
- Thông tin trên Room phải tối giản; chi tiết issue chỉ xuất hiện sau thao tác click.
- Giữ phong cách sáng và native macOS của OpsHub; không chuyển sang dark control-room hoặc pixel-art.
- Không thêm Lottie, Rive hoặc dependency animation mới.

## 3. Bố cục màn hình

### 3.1 Header và workflow summary

Header hiện có tiếp tục nằm ngoài vùng scroll và giữ:

- title `Dev Room`;
- Project `social/socom-issues`;
- thời gian cập nhật gần nhất;
- nút Refresh.

Workflow summary tiếp tục hiển thị năm stage theo thứ tự:

`Todo → Doing → ToTest → Test → Passed`.

Các ô summary được thu gọn để dành phần lớn chiều cao cho căn phòng. Hành vi click để lọc và click lại để bỏ lọc giữ nguyên.

### 3.2 Căn phòng chung

Phần nội dung chính là một office scene duy nhất:

- nền tường sáng và sàn có texture rất nhẹ;
- cửa sổ, đồng hồ và cây xanh dùng làm chi tiết nền;
- các workstation xếp thành grid responsive;
- mỗi workstation gồm Flat Chibi, laptop, bàn và một employee tag nhỏ;
- khoảng cách giữa các bàn đủ để nhân vật không chồng lên nhau;
- khi thay đổi kích thước cửa sổ, số cột giảm nhưng workstation giữ nguyên tỉ lệ và thứ tự nhân viên.

Không dùng container/card riêng bao quanh từng workstation. Nền căn phòng là bề mặt chung liên kết tất cả nhân viên.

## 4. Cấu hình thành viên Dev Room

### 4.1 Nguồn danh sách

Settings bổ sung section `Dev Room Members` dưới phần cấu hình GitLab. Danh sách lấy từ toàn bộ thành viên của Project `social/socom-issues` bằng GitLab Project Members API:

- endpoint `/projects/:id/members/all` để gồm cả thành viên trực tiếp, inherited và invited group members;
- pagination `per_page=100` theo `X-Next-Page`;
- mỗi member có GitLab user ID, display name, username, avatar URL và access level;
- danh sách sắp xếp theo display name, sau đó theo GitLab user ID.

Không lấy danh sách chọn từ open issues, vì cần cấu hình một thành viên trước khi họ được assign task.

### 4.2 Allowlist và persistence

Tạo store riêng cho Dev Room, không đưa cấu hình này vào `GitLabSettings`:

```swift
struct DevRoomVisibilitySettings: Equatable, Sendable {
    let selectedUserIDs: Set<Int>
}

protocol DevRoomVisibilitySettingsStoring {
    func load() -> DevRoomVisibilitySettings
    func save(_ settings: DevRoomVisibilitySettings)
}
```

`DevRoomVisibilitySettingsStore` lưu mảng GitLab user ID trong `UserDefaults`. Mặc định `selectedUserIDs` rỗng, kể cả khi Project đã có thành viên. Thành viên mới cũng mặc định không được chọn.

`ContentView` sở hữu store, load allowlist khi khởi tạo `DevRoomViewModel`, và inject store vào `SettingsView`. Sau khi Settings lưu thành công, callback gọi `DevRoomViewModel.applySelectedUserIDs(_:)`, để cấu hình có hiệu lực ngay mà không cần khởi động lại app.

### 4.3 UI Settings

Section `Dev Room Members` gồm:

- Project cố định `social/socom-issues`;
- search theo display name hoặc username;
- checkbox cho từng member;
- avatar, display name, username, GitLab ID và access level;
- số user đang chọn;
- action `Select All` và `Clear` chỉ thay đổi draft;
- loading, failed + Retry và empty state rõ ràng.

Các checkbox không lưu ngay. Nút Save chung của Settings lưu GitLab URL/token trước; chỉ khi bước này thành công mới lưu allowlist Dev Room và gọi callback cập nhật ViewModel. Nếu lưu GitLab settings lỗi, cả allowlist draft chưa được áp dụng.

Members được tải bằng GitLab connection đã lưu khi mở Settings. Nếu URL/token vừa thay đổi và Save thành công, Settings tải lại members bằng connection mới. Nếu tải members lỗi, Settings giữ selection đã lưu, hiển thị Retry và không được âm thầm ghi allowlist rỗng.

Sau Save thành công, Dev Room áp dụng allowlist trên dữ liệu cache hiện tại. Không bắt buộc gọi lại GitLab issues chỉ để ẩn/hiện user.

### 4.4 Ảnh hưởng tới Dev Room

Chỉ issue có `assignee.id` nằm trong `selectedUserIDs` mới được dùng để tạo Dev Room presentation:

- nhân viên không được chọn không có workstation;
- task của họ không được tính vào `Todo`, `Doing`, `ToTest`, `Test`, `Passed`;
- detail drawer không thể mở cho user bị loại;
- nếu user đang mở drawer bị bỏ chọn sau Save, drawer tự đóng;
- snapshot source từ GitLab vẫn giữ đầy đủ để khi bật lại user có thể trình bày ngay từ cache.

Nếu allowlist rỗng, Dev Room không hiển thị phòng rỗng chung chung mà hiển thị hướng dẫn `Chọn thành viên Dev Room trong Settings`.

## 5. Employee tag tối giản

Employee tag là bảng nổi nhỏ gắn phía trên workstation và chỉ chứa:

- avatar GitLab;
- display name;
- tổng số task đang mở;
- một chấm màu stage đại diện.

Không hiển thị trực tiếp trên Room:

- title hoặc preview issue;
- năm workflow counts của nhân viên;
- role;
- username;
- thời gian cập nhật issue.

Stage đại diện dùng workflow stage tiến xa nhất đang có task của nhân viên. Chấm màu chỉ là tín hiệu visual; dữ liệu chi tiết và đủ năm counts vẫn có trong sidebar.

Click vào employee tag, chibi, laptop hoặc bàn đều chọn cùng một nhân viên và mở detail sidebar.

## 6. Flat Chibi profile

### 6.1 Profile mapping

Mỗi nhân viên có một chibi profile được map theo GitLab user ID hoặc username lấy từ Project Members API. Profile gồm các thuộc tính trình bày, không chứa business data:

- skin tone;
- hair style;
- hair color;
- shirt color;
- phụ kiện tùy chọn như kính hoặc tai nghe.

Profile được chọn thủ công dựa trên avatar GitLab để tạo cảm giác giống nhân viên nhưng vẫn cùng một ngôn ngữ Flat Chibi. Không phân tích khuôn mặt hoặc gọi AI lúc runtime.

### 6.2 Fallback

Nhân viên chưa có mapping vẫn phải xuất hiện. App tạo profile mặc định ổn định từ GitLab user ID:

- chọn một hair style trong bộ có sẵn;
- chọn skin tone, hair color và shirt color trong palette cố định;
- cùng một user ID luôn nhận cùng một profile giữa các lần mở app.

Khi bổ sung mapping thủ công, workstation tự dùng profile mới mà không thay đổi dữ liệu task.

## 7. Detail sidebar

Detail được thay từ panel chiếm layout sang sidebar overlay trượt từ phải vào.

### 7.1 Hành vi

- Sidebar rộng khoảng `360pt`, có thể giảm nhẹ ở cửa sổ hẹp.
- Sidebar phủ lên Room; không làm grid hoặc workstation co và reflow.
- Có scrim mờ nhẹ trên Room để thể hiện focus.
- Đóng bằng nút `×`, click scrim hoặc phím `Esc`.
- Chọn nhân viên khác khi sidebar đang mở sẽ thay nội dung trong cùng sidebar.
- Nếu nhân viên biến mất sau refresh vì không còn task, sidebar tự đóng.

### 7.2 Nội dung

Sidebar hiển thị:

- avatar, display name, username nếu có và tổng task;
- đủ năm workflow counts;
- issue group theo `Todo`, `Doing`, `ToTest`, `Test`, `Passed`;
- mỗi issue có `#iid`, title, thời điểm cập nhật và stage label;
- click issue mở GitLab bằng trình duyệt mặc định.

Khi Room đang lọc stage, group đó được đặt trước nhưng các group khác vẫn xem được. Sidebar tiếp tục read-only.

## 8. Animation và trạng thái

### 8.1 Idle

Flat Chibi giữ animation mức nhẹ:

- hai tay gõ phím lệch nhịp;
- chớp mắt;
- đầu hoặc thân dịch chuyển rất nhỏ;
- laptop thay đổi độ sáng nhẹ.

Nhịp animation tiếp tục xác định từ employee ID. Reduce Motion hoặc cửa sổ inactive sẽ dừng idle animation như behavior hiện tại.

### 8.2 Task thay đổi

Snapshot diff và danh sách employee bị ảnh hưởng giữ nguyên. Khi task thay đổi:

- workstation của đúng nhân viên pulse nhẹ;
- employee tag cập nhật tổng task và chấm stage;
- nhân viên mới xuất hiện bằng transition nhẹ;
- nhân viên hết task biến mất bằng transition nhẹ;
- không animate lại toàn bộ Room.

### 8.3 Filter

Khi chọn workflow stage:

- chỉ workstation của nhân viên có task thuộc stage đó được hiển thị;
- Room giữ nền và cấu trúc chung;
- sidebar của nhân viên không còn trong kết quả tự đóng;
- empty state hiển thị trong office scene, không thay toàn bộ màn hình.

## 9. Component boundary đề xuất

```text
DevRoomView
  ├─ DevRoomHeader
  ├─ DevRoomWorkflowSummary
  ├─ DevRoomOfficeScene
  │    ├─ DevRoomOfficeBackground
  │    └─ DevRoomWorkstation
  │         ├─ DevRoomEmployeeTag
  │         └─ DevRoomFlatChibiView
  └─ DevRoomEmployeeDetailDrawer

DevRoomChibiProfileStore
  ├─ manual profile mapping
  └─ deterministic fallback by employee ID

ContentView
  ├─ DevRoomVisibilitySettingsStore
  ├─ DevRoomViewModel
  └─ SettingsView
       └─ DevRoomMemberSelectionSection

GitLabService
  ├─ open Dev Room issues
  └─ project members/all + pagination
```

`DevRoomServicing` tiếp tục chỉ tải issues. Protocol mới `DevRoomMemberServicing` cung cấp `projectMembers(projectPath:)`; `GitLabService` conform cả hai protocol để Settings không làm thay đổi mock/service contract của ViewModel. Issue aggregation và snapshot diff không đổi contract. Visibility filtering nằm trong ViewModel/presentation state để vẫn giữ full issue cache. Visual profile nằm ở presentation layer và không được đưa vào GitLab issue/domain model.

## 10. Accessibility

- Toàn workstation là một accessibility element có label gồm tên nhân viên và tổng task.
- Employee tag không tạo các element lặp lại riêng nếu workstation đã cung cấp cùng thông tin.
- Sidebar nhận focus khi mở và trả focus về workstation đã chọn khi đóng.
- Nút đóng có accessibility label rõ ràng.
- Stage color luôn đi kèm text/count trong sidebar; không dùng màu làm tín hiệu duy nhất.
- Reduce Motion tiếp tục được tôn trọng cho idle, pulse và drawer transition.
- Checkbox member có label gồm display name, username và trạng thái selected; search và Save dùng keyboard được.

## 11. Không thay đổi

- Project path, query GitLab và pagination.
- Rule issue `opened`, label workflow, assignee và dedupe issue ID.
- Auto-refresh hai phút và Refresh thủ công.
- Top-level menu và các màn Dashboard, Brew, GitLab; Settings chỉ bổ sung section chọn thành viên Dev Room.
- Read-only behavior; không sửa label, assignee hoặc state từ Dev Room.
- Cách mở issue bằng trình duyệt mặc định.

## 12. Acceptance criteria

- Room nhìn như một căn phòng chung có nhiều nhân viên chibi đang làm việc, không phải danh sách card rời rạc.
- Employee tag chỉ có avatar, tên, tổng task và stage dot.
- Click bất kỳ phần nào của workstation mở sidebar overlay từ phải.
- Sidebar không làm Room reflow và đóng được bằng nút, scrim hoặc `Esc`.
- Nhân viên có mapping dùng đúng Flat Chibi profile; nhân viên chưa mapping dùng fallback ổn định.
- Animation gõ phím/chớp mắt vẫn lệch nhịp và dừng khi Reduce Motion hoặc window inactive.
- Filter, refresh, snapshot animation và detail issue giữ nguyên behavior nghiệp vụ hiện có.
- Settings tải đủ toàn bộ Project members qua pagination và cho search, Select All, Clear.
- Member mới mặc định không được chọn; thay đổi checkbox chỉ có hiệu lực sau Save chung.
- Allowlist được lưu theo GitLab user ID và tồn tại sau khi mở lại app.
- Task của user không được chọn không xuất hiện và không được tính vào workflow summary.
- Allowlist rỗng hiển thị hướng dẫn vào Settings; lỗi tải member không ghi đè selection đã lưu.
- Build Debug/Release và toàn bộ test hiện có pass; bổ sung test cho chibi profile fallback và trạng thái mở/đóng sidebar ở seam phù hợp.
