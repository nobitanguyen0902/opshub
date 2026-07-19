# Task 3 Report: Snapshot diff và animation event domain

## Implementation

- Added `DevRoomIssueSnapshot`, `DevRoomSnapshot`, `DevRoomChangeSet`, and `DevRoomSnapshotDiffer`.
- `DevRoomSnapshot(data:)` captures each issue by stable issue ID.
- The differ marks affected employee IDs only when an issue is added, removed, reassigned, or changes workflow stage.
- Title and timestamp are retained in the snapshot but do not produce an animation event.

## TDD

- RED: `swift test --filter DevRoomSnapshotDifferTests` failed because the snapshot types and differ did not exist.
- GREEN: the same command passed with 6 tests after the implementation.

## Verification

- `swift test --filter DevRoomSnapshotDifferTests`: passed, 6 tests.
- `swift test`: passed, 92 tests.
- `git diff --check`: passed.

## Files

- `Sources/OpsHub/Features/DevRoom/Models/DevRoomSnapshotDiffer.swift`
- `Tests/OpsHubTests/DevRoomSnapshotDifferTests.swift`

## Self-review

- New, removed, stage-changed, and reassigned issues insert the required old and/or new employee IDs into a set.
- Unchanged and title/timestamp-only snapshots leave the set empty.
- The implementation is pure domain logic and does not alter data fetching or UI behavior.

## Concerns

- None within this task's domain-only scope.
