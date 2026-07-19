### Task 8: Final regression, UI polish và acceptance verification

**Files:**
- Modify only if verification exposes a Dev Room defect:
  - Sources/OpsHub/Features/DevRoom/**
  - Tests/OpsHubTests/DevRoom*Tests.swift
- Do not modify GitLab dashboard behavior to fix a Dev Room-only defect.

**Interfaces:**
- Consumes: toàn bộ Tasks 1-7.
- Produces: verified Dev Room feature matching the approved spec.

- [ ] **Step 1: Run all targeted suites**

Run:

~~~bash
swift test --filter DevRoom
swift test --filter AppSectionTests
swift test --filter GitLabIssueTabTests
swift test --filter GitLabServiceTests
swift test --filter GitLabDashboardViewModelTests
~~~

Expected: tất cả PASS. Nếu fail, thêm regression test đúng behavior rồi sửa tối thiểu trong Dev Room boundary.

- [ ] **Step 2: Run full verification gate**

Run:

~~~bash
swift test
swift build
swift build -c release
git diff --check
~~~

Expected: full test suite PASS; debug/release build succeed; không có whitespace error.

- [ ] **Step 3: Manual acceptance pass**

Run:

~~~bash
swift run OpsHub
~~~

Verify:

1. Sidebar có Dashboard, Dev Room, Brew, GitLab, Settings theo đúng order.
2. Các màn hình cũ mở và hoạt động như trước.
3. Dev Room header hiển thị social/socom-issues, timestamp và Refresh cố định.
4. Chỉ issue Open có workflow label + assignee được tính.
5. Todo, Doing, ToTest, Test, Passed có count đúng và filter toggle đúng.
6. Employee không task không xuất hiện; mỗi employee chỉ một bàn.
7. Detail panel group task đúng và link mở GitLab.
8. Reopen Dev Room dùng cache; manual Refresh force fetch.
9. Để Dev Room hiển thị đủ 2 phút xác nhận auto-refresh; chuyển menu trước 2 phút xác nhận loop bị cancel.
10. Animation first load, task change, Reduce Motion và inactive window đúng acceptance criteria.
11. Initial error, stale cache và empty state có nội dung rõ ràng.

- [ ] **Step 4: Review diff chỉ trong scope**

Run:

~~~bash
git status --short
git diff --stat
git diff -- Sources/OpsHub/App/ContentView.swift Sources/OpsHub/Features/DevRoom Sources/OpsHub/Features/GitLab/Services/GitLabServices.swift Tests/OpsHubTests
~~~

Expected: không có refactor ngoài scope, secret, token, generated binary hoặc thay đổi GitLab UI/tab behavior.

- [ ] **Step 5: Commit final verification fixes nếu có**

Nếu Step 1-4 không tạo thay đổi, bỏ qua commit này. Nếu có regression fix:

~~~bash
git add Sources/OpsHub/Features/DevRoom Tests/OpsHubTests
git commit -m "fix(dev-room): complete acceptance verification"
~~~
