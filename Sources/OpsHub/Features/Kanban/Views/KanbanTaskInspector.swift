import SwiftUI

enum KanbanInspectorLayout {
    static let preferredWidth: CGFloat = 460
    static let horizontalInset: CGFloat = 16

    struct Placement: Equatable {
        let width: CGFloat
        let trailingInset: CGFloat
    }

    static func placement(for availableWidth: CGFloat) -> Placement {
        let boundedWidth = max(0, availableWidth)
        guard boundedWidth < preferredWidth + (horizontalInset * 2) else {
            return Placement(width: preferredWidth, trailingInset: 0)
        }
        let inset = min(horizontalInset, boundedWidth / 2)
        return Placement(width: boundedWidth - (inset * 2), trailingInset: inset)
    }
}

struct KanbanInspectorBackdrop: View {
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(0.22)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .accessibilityHidden(true)
    }

    func dismiss() { onDismiss() }
}

enum KanbanInspectorFocusRouter {
    static func target(
        previousCardID: KanbanCardID?,
        selectedCardID: KanbanCardID?,
        displayedCardIDs: Set<KanbanCardID>
    ) -> KanbanCardID? {
        guard selectedCardID == nil,
              let previousCardID,
              displayedCardIDs.contains(previousCardID) else {
            return nil
        }
        return previousCardID
    }
}

enum KanbanInspectorTransitionKind: Equatable {
    case fade, slideAndFade
}

struct KanbanInspectorTransitionPolicy: Equatable {
    let kind: KanbanInspectorTransitionKind
    let duration: Double
    let animatesBoardSurface: Bool

    static func policy(reduceMotion: Bool) -> KanbanInspectorTransitionPolicy {
        reduceMotion
            ? .init(kind: .fade, duration: 0.12, animatesBoardSurface: false)
            : .init(kind: .slideAndFade, duration: 0.20, animatesBoardSurface: false)
    }

    var transition: AnyTransition {
        switch kind {
        case .fade: .opacity
        case .slideAndFade: .move(edge: .trailing).combined(with: .opacity)
        }
    }
}

enum KanbanLogFollowPolicy {
    static let threshold: CGFloat = 24

    static func shouldFollow(distanceFromBottom: CGFloat) -> Bool {
        distanceFromBottom <= threshold
    }
}

private struct KanbanLogBottomOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct KanbanTaskInspector: View {
    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case runs = "Runs"
        case liveLog = "Live Log"

        var id: Self { self }
    }

    @ObservedObject var model: KanbanViewModel
    let card: KanbanCardViewData
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var isHeadingFocused: Bool
    @State private var selectedTab: Tab = .overview
    @State private var logPollTask: Task<Void, Never>?
    @State private var distanceFromBottom: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Picker("Inspector section", selection: $selectedTab) {
                ForEach(Tab.allCases) { tab in Text(tab.rawValue).tag(tab) }
            }
            .pickerStyle(.segmented)

            Group {
                switch selectedTab {
                case .overview: overview
                case .runs: runs
                case .liveLog: liveLog
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .onAppear {
            isHeadingFocused = true
            Task { await model.loadSelectedDetail() }
            updateLogPolling()
        }
        .onChange(of: selectedTab) { _, _ in updateLogPolling() }
        .onDisappear { stopLogPolling() }
        .onExitCommand(perform: close)
        .animation(.easeOut(duration: reduceMotion ? 0.12 : 0.20), value: selectedTab)
    }

    func close() { onClose() }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(.title2, design: .monospaced).bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($isHeadingFocused)
                    Text(card.displayID)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(card.isWorkflowOwned ? "Managed workflow" : "External Hermes task")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(card.isWorkflowOwned ? OpsHubTerminalTheme.accent : .secondary)
                }
                Spacer(minLength: 0)
                Button(action: close) {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close task inspector")
                .accessibilityHint("Press Escape to close")
            }
            actions
        }
    }

    @ViewBuilder
    private var actions: some View {
        if card.isWorkflowOwned, !card.availableActions.isEmpty {
            HStack(spacing: 8) {
                if card.availableActions.contains(.start) {
                    Button("Start") { Task { await model.startSelected() } }
                }
                if card.availableActions.contains(.approve) {
                    Button("Approve & Continue") { Task { await model.approveSelected() } }
                }
                if card.availableActions.contains(.retry) {
                    Button("Retry") { Task { await model.retrySelected() } }
                }
                if card.availableActions.contains(.cancel) {
                    Button("Cancel Run", role: .destructive) { Task { await model.cancelSelected() } }
                }
            }
            .disabled(model.activeAction != nil)
            .accessibilityElement(children: .contain)
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                inspectorMetadata("Workspace", value: card.workspacePath ?? "Unavailable")
                inspectorMetadata("Status", value: card.stageLabel ?? card.column.rawValue.capitalized)
                inspectorMetadata("Priority", value: card.priority.title)

                if let detail = model.selectedHermesDetail {
                    if let summary = detail.latestSummary, !summary.isEmpty {
                        inspectorMetadata("Latest summary", value: summary)
                    }
                    if !detail.comments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Comments").font(.system(.headline, design: .monospaced))
                            ForEach(Array(detail.comments.enumerated()), id: \.offset) { _, comment in
                                Text("\(comment.author): \(comment.body)")
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                } else {
                    ProgressView("Loading task details…")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var runs: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                let attempts = model.selectedHermesDetail?.runs ?? []
                if attempts.isEmpty {
                    ContentUnavailableView("No runs yet", systemImage: "play.circle")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else {
                    ForEach(attempts) { run in runRow(run) }
                }
            }
        }
    }

    private var liveLog: some View {
        GeometryReader { viewport in
            ScrollViewReader { reader in
                ScrollView {
                    VStack(spacing: 0) {
                        Text(model.selectedLog ?? "Waiting for live log…")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(OpsHubTerminalTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))

                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: KanbanLogBottomOffsetPreferenceKey.self,
                                value: proxy.frame(in: .named("kanban-live-log")).maxY
                            )
                        }
                        .frame(height: 1)
                        .id("log-bottom")
                    }
                }
                .coordinateSpace(name: "kanban-live-log")
                .onPreferenceChange(KanbanLogBottomOffsetPreferenceKey.self) { bottomOffset in
                    distanceFromBottom = max(0, bottomOffset - viewport.size.height)
                }
                .onChange(of: model.selectedLog) { _, _ in
                    guard KanbanLogFollowPolicy.shouldFollow(distanceFromBottom: distanceFromBottom) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                        reader.scrollTo("log-bottom", anchor: .bottom)
                    }
                }
                .accessibilityLabel("Live task log")
            }
        }
    }

    private func inspectorMetadata(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func runRow(_ run: HermesKanbanRun) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(run.outcome ?? run.status)
                    .font(.system(.callout, design: .monospaced).weight(.bold))
                Spacer()
                Text(run.profile ?? "Unknown role")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(elapsed(for: run))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            if let summary = run.summary ?? run.metadata?.summary, !summary.isEmpty {
                Text(summary).font(.system(.caption, design: .monospaced))
            }
            if let error = run.error, !error.isEmpty {
                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OpsHubTerminalTheme.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(OpsHubTerminalTheme.borderSubtle) }
        .accessibilityElement(children: .combine)
    }

    private func elapsed(for run: HermesKanbanRun) -> String {
        let end = run.endedAtDate ?? Date()
        let seconds = max(0, Int(end.timeIntervalSince(run.startedAtDate ?? end)))
        return "Elapsed \(seconds / 60)m \(seconds % 60)s"
    }

    private func updateLogPolling() {
        stopLogPolling()
        guard selectedTab == .liveLog else { return }
        logPollTask = Task {
            while !Task.isCancelled {
                await model.loadSelectedLog()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private func stopLogPolling() {
        logPollTask?.cancel()
        logPollTask = nil
    }
}
