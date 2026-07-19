# Visual Task 2 Report: Persisted Allowlist and Visible Dev Room Projection

## Status

Completed. Initial allowlist implementation is in `30e2db5`; the follow-up summary projection fix is recorded below.

## Changed Files

- `Sources/OpsHub/Core/Settings/DevRoomVisibilitySettingsStore.swift`
  - Added the typed `UserDefaults` allowlist settings value, store protocol, deterministic save, and empty default.
- `Sources/OpsHub/Features/DevRoom/Models/DevRoomModels.swift`
  - Added `DevRoomData.filtered(userIDs:)` to project full data into the configured visible subset.
- `Sources/OpsHub/Features/DevRoom/ViewModels/DevRoomViewModel.swift`
  - Added allowlist state, `visibleData`, `hasConfiguredMembers`, apply behavior, and selection cleanup against the visible projection.
- `Sources/OpsHub/Features/DevRoom/Views/DevRoomView.swift`
  - Passes the visible projection to the workflow summary, so summary counts exclude hidden members.
- `Tests/OpsHubTests/DevRoomVisibilitySettingsStoreTests.swift`
  - Added empty-default and sorted persistence regression coverage.
- `Tests/OpsHubTests/DevRoomViewModelTests.swift`
  - Added allowlist projection and empty-allowlist drawer cleanup coverage; updated display/selection tests with explicit configured IDs.
- `Tests/OpsHubTests/DevRoomViewTests.swift`
  - Added UI-facing regression coverage that verifies the workflow summary input excludes hidden assignees.

## TDD Evidence

1. `swift test --filter DevRoomVisibilitySettingsStoreTests`
   - Before implementation: failed as expected because `DevRoomVisibilitySettingsStore` and `DevRoomVisibilitySettings` did not exist.
   - After implementation: passed (2 tests, 0 failures).
2. `swift test --filter DevRoomViewTests`
   - Before the follow-up fix: failed as expected because `DevRoomView` did not expose the workflow summary projection used by the UI.
   - After implementation: passed (1 test, 0 failures), proving the summary input has zero Todo items for a hidden Todo assignee and one Passed item for the selected assignee.

## Verification

- `swift test --filter DevRoomVisibilitySettingsStoreTests` — passed (2 tests, 0 failures).
- `swift test --filter DevRoomViewModelTests` — passed (13 tests, 0 failures).
- `swift test --filter DevRoomViewTests` — passed (1 test, 0 failures).
- `git diff --check` — passed with no whitespace errors.

## Self-review

- `data` and `DevRoomSnapshot` always retain the complete GitLab result, so re-enabling a member never requires a refresh and snapshot diffs keep the full baseline.
- `visibleData`, workflow counts through `visibleData`, employee display, and selected employee lookup are projected through the configured allowlist.
- The workflow summary now receives the view's visible projection rather than full cached data, while `data` and snapshot construction remain unfiltered.
- Empty allowlists intentionally produce no visible employees; applying one clears a selection that is no longer displayed.
- Settings persistence stores canonical sorted integer IDs and restores them as a `Set`.

## Concerns

No concerns. Settings UI wiring is intentionally outside this task's scope. This report and existing `.superpowers`/Xcode local changes are intentionally excluded from the commit.
