# Shared Feature Header Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Đồng bộ header của Dashboard, Brew, GitLab, Dev Room và Settings theo Dashboard hiện tại mà không thay đổi hành vi của feature.

**Architecture:** Tạo `OpsHubFeatureHeader` trong shared components để sở hữu typography, surface, spacing và responsive composition. Các feature tiếp tục sở hữu controls, bindings, async actions và trạng thái lỗi/loading, rồi truyền chúng vào các `@ViewBuilder` slot của component.

**Tech Stack:** Swift 6, SwiftUI, macOS 14+, Swift Package Manager, XCTest.

## Global Constraints

- Dashboard hiện tại là source of truth cho visual hierarchy.
- Không thay đổi ViewModel, service, API, navigation, keyboard shortcut hoặc workflow.
- Không thêm dependency hoặc framework snapshot testing.
- Giữ semantic SwiftUI controls và accessibility labels hiện có.
- Không chỉnh sửa file trạng thái Xcode của người dùng tại `.swiftpm/xcode/package.xcworkspace/xcuserdata`.
- Không commit, push, mở PR hoặc tạo release nếu người dùng chưa yêu cầu.

---

## File Map

- Create `Sources/OpsHub/Shared/Components/OpsHubFeatureHeader.swift`: component header dùng chung, generic slots và previews.
- Modify `Sources/OpsHub/Shared/Components/DashboardView.swift`: chuyển header source-of-truth sang component shared.
- Modify `Sources/OpsHub/Shared/Components/SettingsView.swift`: áp dụng header shared không có controls.
- Modify `Sources/OpsHub/Features/Brew/Views/BrewListView.swift`: áp dụng header shared, giữ ba Brew actions.
- Modify `Sources/OpsHub/Features/DevRoom/Components/DevRoomHeader.swift`: áp dụng header shared, giữ refresh/update/stale state.
- Modify `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceHeader.swift`: áp dụng header shared, giữ search/scope/refresh.
- Keep `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift` unchanged; `mode` remains consumed by `GitLabWorkspaceHeader`.
- No test file is created: repository không có view-inspection/snapshot dependency; compiler, previews và existing behavioral tests là verification phù hợp cho modifier-only UI work.

### Task 1: Add the shared feature-header component

**Files:**
- Create: `Sources/OpsHub/Shared/Components/OpsHubFeatureHeader.swift`

**Interfaces:**
- Consumes: `OpsHubTerminalTheme`, `opsHubTerminalSurface(isEmphasized:)`.
- Produces:
  - `OpsHubFeatureHeader<Controls: View, Status: View>`
  - initializer with `eyebrow: String`, `title: String`, `metadata: String`, `controls`, and `status`
  - overload for controls without status
  - overload for title-only headers with neither controls nor status

- [ ] **Step 1: Confirm the current package compiles before adding the component**

Run:

```bash
swift build
```

Expected: build succeeds. If it fails, record the baseline failure before making source changes.

- [ ] **Step 2: Create `OpsHubFeatureHeader.swift` with generic view slots**

Implement this component shape:

```swift
import SwiftUI

struct OpsHubFeatureHeader<Controls: View, Status: View>: View {
    let eyebrow: String
    let title: String
    let metadata: String
    private let controls: Controls
    private let status: Status

    init(
        eyebrow: String,
        title: String,
        metadata: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder status: () -> Status
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.metadata = metadata
        self.controls = controls()
        self.status = status()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    titleBlock
                    Spacer(minLength: 12)
                    controls
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    controls
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            status
        }
        .padding(16)
        .opsHubTerminalSurface(isEmphasized: true)
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(">")
                    .foregroundStyle(OpsHubTerminalTheme.accent)
                Text(eyebrow)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .monospaced))

            Text(metadata)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}
```

Add two constrained initializers:

```swift
extension OpsHubFeatureHeader where Status == EmptyView {
    init(
        eyebrow: String,
        title: String,
        metadata: String,
        @ViewBuilder controls: () -> Controls
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            metadata: metadata,
            controls: controls,
            status: { EmptyView() }
        )
    }
}

extension OpsHubFeatureHeader where Controls == EmptyView, Status == EmptyView {
    init(eyebrow: String, title: String, metadata: String) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            metadata: metadata,
            controls: { EmptyView() },
            status: { EmptyView() }
        )
    }
}
```

- [ ] **Step 3: Add focused previews**

Add previews for:

```swift
#Preview("Feature header — controls") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / DASHBOARD",
        title: "Sprint health",
        metadata: "milestone=Sprint 32 · updated=10:30"
    ) {
        Button("Refresh", systemImage: "arrow.clockwise") {}
            .buttonStyle(.plain)
            .opsHubTerminalControl()
    }
    .padding()
    .frame(width: 900)
}

#Preview("Feature header — narrow") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / BREW",
        title: "Package manager",
        metadata: "source=homebrew · mode=local"
    ) {
        HStack {
            Button("Refresh") {}
            Button("Check Outdated") {}
            Button("Update All") {}
        }
        .buttonStyle(.plain)
    }
    .padding()
    .frame(width: 520)
}

#Preview("Feature header — no controls") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / SETTINGS",
        title: "Preferences",
        metadata: "Configure OpsHub and local integrations."
    )
    .padding()
    .frame(width: 700)
}
```

- [ ] **Step 4: Compile the generic component**

Run:

```bash
swift build
```

Expected: build succeeds without generic inference or result-builder errors.

### Task 2: Migrate Dashboard and Settings

**Files:**
- Modify: `Sources/OpsHub/Shared/Components/DashboardView.swift:37-106`
- Modify: `Sources/OpsHub/Shared/Components/SettingsView.swift:135-148`

**Interfaces:**
- Consumes: `OpsHubFeatureHeader` from Task 1.
- Preserves: Dashboard milestone selection/refresh/status behavior and Settings form actions.

- [ ] **Step 1: Replace the Dashboard header shell**

Keep `milestonePicker`, the Refresh button implementation, accessibility label,
accessibility hint, and `statusBanner` calls unchanged. Replace only the outer
title/layout/surface code:

```swift
private var header: some View {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / DASHBOARD",
        title: "Sprint health",
        metadata: headerMetadata
    ) {
        HStack(spacing: 0) {
            milestonePicker

            Divider()
                .frame(height: 22)
                .accessibilityHidden(true)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isLoading {
                        LoadingSpinnerView()
                            .accessibilityHidden(true)
                    }
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .frame(width: 116)
                .frame(minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isLoading)
            .accessibilityLabel(
                viewModel.isLoading ? "Refreshing Dashboard" : "Refresh Dashboard"
            )
            .accessibilityHint("Reloads milestones and sprint metrics from GitLab")
        }
        .opsHubTerminalControlGroup()
    } status: {
        if case let .stale(message) = viewModel.milestoneState {
            statusBanner(
                message: "Milestone list is stale. \(message)",
                systemImage: "exclamationmark.triangle",
                color: .orange
            )
        } else if case let .failed(message) = viewModel.milestoneState {
            statusBanner(
                message: message,
                systemImage: "xmark.octagon",
                color: .red
            )
        }
    }
}
```

- [ ] **Step 2: Replace the Settings title block**

Use the no-controls initializer:

```swift
private var settingsHeader: some View {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / SETTINGS",
        title: "Preferences",
        metadata: "Personalize OpsHub and configure local integrations."
    )
}
```

Leave Save and Test Connection in the form body.

- [ ] **Step 3: Run Dashboard and Settings behavioral tests**

Run:

```bash
swift test --filter SprintDashboard
swift test --filter AppearanceSettingsStoreTests
swift test --filter GitLabSettingsStoreTests
swift build
```

Expected: all selected tests and build pass.

### Task 3: Migrate Brew and Dev Room

**Files:**
- Modify: `Sources/OpsHub/Features/Brew/Views/BrewListView.swift:56-96`
- Modify: `Sources/OpsHub/Features/DevRoom/Components/DevRoomHeader.swift:3-52`

**Interfaces:**
- Consumes: `OpsHubFeatureHeader`.
- Preserves: Brew command actions/confirmation/shortcut and Dev Room refresh/stale/update state.

- [ ] **Step 1: Wrap Brew controls in the shared header**

Replace the current header layout with:

```swift
private var header: some View {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / BREW",
        title: "Package manager",
        metadata: "source=homebrew · mode=local"
    ) {
        HStack {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.loadPackages() }
            }
            .buttonStyle(.plain)
            .opsHubTerminalControl()
            .keyboardShortcut("r", modifiers: .command)

            Button("Check Outdated", systemImage: "checkmark.circle") {
                Task { await viewModel.checkOutdated() }
            }
            .buttonStyle(.plain)
            .opsHubTerminalControl()

            Button("Update All", systemImage: "arrow.up.circle") {
                isShowingUpdateAllConfirmation = true
            }
            .buttonStyle(.plain)
            .opsHubTerminalControl()
            .disabled(
                viewModel.outdatedCount == 0
                    || viewModel.isLoading
                    || viewModel.isUpdatingAll
            )
        }
        .disabled(viewModel.isLoading)
    }
}
```

- [ ] **Step 2: Move Dev Room update information into metadata/status slots**

Add a computed metadata string:

```swift
private var metadata: String {
    let source = "project=\(GitLabWorkflowProject.path) · source=assigned-open-issues"
    guard let lastUpdated else { return "\(source) · updated=never" }
    return "\(source) · updated=\(lastUpdated.formatted(date: .omitted, time: .shortened))"
}
```

Replace the header body:

```swift
var body: some View {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / DEV ROOM",
        title: "Team workspace",
        metadata: metadata
    ) {
        Button(action: onRefresh) {
            Label(
                isRefreshing ? "Đang cập nhật" : "Refresh",
                systemImage: "arrow.clockwise"
            )
        }
        .buttonStyle(.plain)
        .opsHubTerminalControl()
        .disabled(isRefreshing)
        .accessibilityLabel(isRefreshing ? "Đang cập nhật Dev Room" : "Refresh Dev Room")
    } status: {
        if isStale {
            Label("Dữ liệu có thể đã cũ", systemImage: "exclamationmark.triangle")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.orange)
        }
    }
}
```

- [ ] **Step 3: Run Brew and Dev Room behavioral tests**

Run:

```bash
swift test --filter BrewServiceTests
swift test --filter DevRoom
swift build
```

Expected: all selected tests and build pass; no service or ViewModel file changes.

### Task 4: Migrate the GitLab workspace header

**Files:**
- Modify: `Sources/OpsHub/Features/GitLab/Components/GitLabWorkspaceHeader.swift:1-143`
- Verify unchanged: `Sources/OpsHub/Features/GitLab/Views/GitLabDashboardView.swift:55-67`

**Interfaces:**
- Consumes: `OpsHubFeatureHeader`, existing `GitLabWorkspaceLayoutMode`, bindings and GitLab terminal controls.
- Preserves: `selectedScope`, `searchText`, project menu, stale metadata, loading state and refresh action.

- [ ] **Step 1: Replace the GitLab-specific title/layout shell**

Keep the existing `controls` property and `lastUpdatedText`. Replace `body` and
remove `titleBlock`:

```swift
var body: some View {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / GITLAB",
        title: "Workspace",
        metadata: metadata
    ) {
        controls
    }
}

private var metadata: String {
    var parts = [
        "scope=\(selectedScope.title)",
        "updated=\(lastUpdatedText)"
    ]
    if hasStaleData {
        parts.append("status=stale")
    }
    return parts.joined(separator: " · ")
}
```

The `mode` property remains because `controls` uses it to size search. Do not
change the project `Menu`, search binding, refresh label or accessibility
attributes.

- [ ] **Step 2: Preserve narrow-mode sizing**

Verify these existing constraints remain in `controls`:

```swift
.frame(minWidth: mode == .narrow ? 180 : 220, maxWidth: 300)
```

and:

```swift
.frame(minWidth: 240, maxWidth: 240, minHeight: 42, alignment: .leading)
```

The shared `ViewThatFits` owns whether title and controls are horizontal or
stacked; `GitLabWorkspaceLayoutMode` still owns internal control width.

- [ ] **Step 3: Update GitLab header previews**

Keep the existing wide and narrow previews. They must continue constructing
`GitLabWorkspaceHeader` with the same arguments so the public feature interface
does not drift.

- [ ] **Step 4: Run GitLab-focused verification**

Run:

```bash
swift test --filter GitLabWorkspace
swift test --filter GitLabDashboardViewModelTests
swift build
```

Expected: selected tests and build pass. `GitLabDashboardView.header(mode:)`
requires no behavioral change.

### Task 5: Full verification and scope audit

**Files:**
- Verify all files listed in the File Map.
- Verify untouched user file: `.swiftpm/xcode/package.xcworkspace/xcuserdata/nobitanguyen.xcuserdatad/UserInterfaceState.xcuserstate`

**Interfaces:**
- Consumes: completed migrations from Tasks 1-4.
- Produces: verified shared visual header with unchanged feature behavior.

- [ ] **Step 1: Run the full test suite**

Run:

```bash
swift test
```

Expected: all tests pass.

- [ ] **Step 2: Run debug and release builds**

Run:

```bash
swift build
swift build -c release
```

Expected: both configurations build successfully.

- [ ] **Step 3: Check formatting and accidental changes**

Run:

```bash
git diff --check
git status --short
git diff --stat
git diff -- Sources/OpsHub docs/superpowers
```

Expected:

- no whitespace errors;
- source diff is limited to the shared header and five feature integrations;
- the pre-existing Xcode `UserInterfaceState.xcuserstate` modification remains
  untouched;
- no ViewModel, service, model, package or release file changes.

- [ ] **Step 4: Perform manual visual and interaction QA**

Run:

```bash
swift run OpsHub
```

Check:

- Dashboard, Brew, GitLab, Dev Room and Settings share the same eyebrow/title/
  metadata hierarchy, emphasized surface and 16pt inner padding.
- Resize the window until controls move below the title without clipping.
- Confirm light and dark appearances preserve readable borders and text.
- Confirm Dashboard milestone selection and Refresh still work.
- Confirm Brew Refresh, Check Outdated and Update All confirmation still work;
  do not execute an actual package upgrade solely for visual validation.
- Confirm GitLab Search, project selector and Refresh still work.
- Confirm Dev Room Refresh loading/disabled state and stale label still render.
- Confirm Settings Save/Test Connection remain in the form, not in the header.
- Confirm keyboard focus, labels and disabled states remain visible.

- [ ] **Step 5: Hand off without committing**

Report:

- files changed;
- test/build commands and results;
- visual QA performed or any reason it could not be performed;
- residual risk limited to manual SwiftUI layout validation if the app cannot
  be launched in the current environment.

Do not commit, push, open a PR or create a release.
