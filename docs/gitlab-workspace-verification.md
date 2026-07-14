# GitLab Workspace Verification

Date: 2026-07-14  
Branch: `codex/gitlab-workspace-layout`

## Automated evidence

- `swift test`: the full suite passes, including multi-project identity, scope-race, current-scope cache, Overview search and cross-source deduplication checks.
- `swift build`: debug build passed after every Work Item.
- `swift build -c release`: passed as the final compiler/optimization check.
- Adaptive layout boundaries are covered at 720/960/1440-equivalent modes by `GitLabWorkspaceStateTests`.
- Refresh resilience, duplicate-load prevention, same-scope reopen caching, selection/filter retention and summary routing are covered by `GitLabDashboardViewModelTests`.
- Action queue priority, deduplication, project scoping and a 2,000-item transformation are covered by `GitLabActionQueueTests`.
- Project catalog request reuse and partial pipeline results are covered by `GitLabServiceTests`.

## Accessibility audit

- Keyboard: native `Button`, `Picker`, `TextField` and segmented controls provide Enter/Space behavior and visible system focus. There is no modal state or custom focus trap; Escape has no custom state to dismiss.
- Focus order follows source order: header controls, section navigation, summary actions, filters, rows, then optional row actions.
- VoiceOver: rows expose one composed summary and an action hint; summary metrics expose label/value; navigation exposes selection and counts; refresh exposes refreshing state; decorative icons are hidden.
- Pointer targets use a minimum 44-point hit area for rows and secondary actions.
- Status meaning is encoded by text and SF Symbol as well as color.
- Reduce Motion disables row hover/selection animation. The shell uses no essential motion.

## Appearance and responsive audit

- Colors use semantic SwiftUI foreground/background styles and adaptive design tokens; no fixed light-only surface is used.
- Light/dark, Increase Contrast and Reduce Transparency remain readable because text/status labels do not depend on material or color alone.
- Narrow (<840), compact (840–1179), and wide (>=1180) layout contracts are centralized in `GitLabAdaptiveLayout`.
- 720: header stacks, summary becomes a two-column grid, rows stack metadata, issue tabs/navigation scroll horizontally by design.
- 960: compact spacing and unified rows remain single-scroll-page content.
- 1440: header is horizontal, summary uses one row, Overview previews use two equal-width columns.
- Text can wrap for titles and labels; controls retain native text scaling behavior.

## Performance and data behavior

- Lists use `LazyVStack`; summary uses `LazyVGrid` outside wide mode.
- Action queue transformation is deterministic, deduplicated and covered with 2,000 representative items.
- The app-owned `GitLabDashboardViewModel` keeps the currently loaded scope in memory while navigating between sidebar screens.
- Reopening GitLab with the same scope does not fetch again; changing scope or using Refresh starts a new load cycle.
- Project membership data is actor-cached within a refresh cycle, shared by project selection and pipeline loading, then invalidated for the next user refresh.
- Refresh is guarded against duplicate concurrent load cycles.
- Partial pipeline failures retain successful project results and identify failed projects.
- Background refresh retains previous data, selection, selected workflow tab and section filters.

## Regression checklist

- [x] Five workspace destinations route to real content.
- [x] Pending remains an Overview metric and notification-derived work remains in Action queue.
- [x] Overview uses the common WorkItemList/WorkItemRow contract with two preview sections.
- [x] Merge Requests, Reviews, Issues and Pipelines use the common list contract.
- [x] Reopening GitLab with the same selected scope reuses in-memory data until Refresh or scope change.
- [x] Issue workflow labels remain: Assign me, Test, Passed, Build, Bug Pro.
- [x] Search/filter state is scoped per section.
- [x] Stale and partial data warnings do not erase usable data.
- [x] Legacy dashboard card components have no remaining references.

## Manual release walkthrough

Before distributing a signed build, perform a final interactive pass with VoiceOver and the macOS accessibility appearance toggles on a real display. This repository-level run verifies the implementation contract and automated behavior; it cannot observe spoken output or display calibration from the command-line environment.
