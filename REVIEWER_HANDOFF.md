# Reviewer Handoff

## Summary
Đã sửa projection của Kanban board để ẩn local workflow có references nhưng toàn bộ Hermes task tương ứng không còn trong snapshot hiện tại. Workflow chưa có reference vẫn hiển thị, và workflow nhiều references vẫn hiển thị khi bất kỳ referenced task nào còn tồn tại.

## Files Changed
- `Sources/OpsHub/Features/Kanban/ViewModels/KanbanViewModel.swift`
- `Tests/OpsHubTests/KanbanViewModelTests.swift`
- `REVIEWER_HANDOFF.md`

## Main Changes
- Tạo tập Hermes task IDs từ kết quả `listTasks` và dùng predicate cục bộ khi project workflow cards.
- Giữ nguyên `lastWorkflows`, duplicate suppression qua `internalTaskIDs`, current-stage task lookup, sorting, actions và refresh-failure behavior.
- Thêm regression tests cho orphan blocked/needsAttention workflows, draft không có reference, và multi-reference workflow có surviving non-current-stage task.
- Không thay đổi persistence, schema, coordinator, Hermes API/CLI hoặc UI layout.

## Testing
- RED: focused 3 regression tests — 1 failure đúng kỳ vọng vì orphan workflows vẫn hiển thị; 2 preservation tests pass.
- `swift test --filter KanbanViewModelTests` — passed, 23 tests.
- `swift test` — passed, 330 tests.
- `swift build` — passed.
- `swift build -c release` — passed.
- `git diff --check` — passed.

## Manual Verification
Not run. Reviewer có thể chạy app, tạo/quan sát workflow có stale Hermes references và refresh board để xác nhận card biến mất mà workflow persistence không bị xóa.

## Notes
Predicate kiểm tra tất cả `stageReferences`, không chỉ reference của current stage. Referenced Hermes task vẫn bị suppress khỏi external-card projection như trước.

## Remaining Issues
None.
