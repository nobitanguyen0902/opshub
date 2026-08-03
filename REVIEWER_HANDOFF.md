# Reviewer Handoff

## Summary
- Fixed Kanban SQLite path resolution to use `FileManager.default.homeDirectoryForCurrentUser`.
- Added diagnostic logging for resolved path and `fileExists`.
- Opened the database with `SQLITE_OPEN_READONLY`.
- Added regression tests for default path resolution and database-open failure.

## Files Changed
- `Sources/OpsHub/Features/Kanban/Services/KanbanSQLiteReader.swift`
- `Tests/OpsHubTests/KanbanTests.swift`

## Verification
- `swift build` — passed
- `swift test --filter KanbanSQLiteReaderTests` — 4 tests passed
- `swift test` — 221 tests passed
- `swift build -c release` — passed
- `git diff --check` — passed

## Sandbox / Entitlements
No `.entitlements` file exists in the repository. The Swift Package build generated `OpsHub-entitlement.plist`; no sandbox entitlement was added or changed because this task only requested diagnosis and the current project has no checked-in app entitlement configuration.

## Review Notes
Please verify the packaged application’s App Sandbox configuration and grant read access to `~/.hermes` if sandboxing is enabled in the distribution target. The reader now reports the resolved path and existence status, which should make permission failures distinguishable from missing files.

## Remaining Issues
The packaged app’s signing/sandbox configuration is outside the Swift Package source tree and was not modified.

## Changed Files / Tests
- `Sources/OpsHub/Features/Kanban/Services/KanbanSQLiteReader.swift`
- `Tests/OpsHubTests/KanbanTests.swift`
- `swift build`
- `swift test --filter KanbanSQLiteReaderTests`
- `swift test`
- `swift build -c release`
- `git diff --check`
