import SwiftUI

struct KanbanView: View {
    @StateObject private var model: KanbanViewModel
    @State private var collapsedColumns: Set<KanbanColumn>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusedCardID: KanbanCardID?
    @AccessibilityFocusState private var focusedHeaderControl: KanbanNewTaskFocusTarget?

    private let columnPreferences: KanbanColumnPreferences

    init(
        model: KanbanViewModel = KanbanViewModel(),
        columnPreferences: KanbanColumnPreferences = KanbanColumnPreferences()
    ) {
        _model = StateObject(wrappedValue: model)
        self.columnPreferences = columnPreferences
        _collapsedColumns = State(initialValue: columnPreferences.collapsedColumns)
    }

    var body: some View {
        let inspectorPolicy = KanbanInspectorTransitionPolicy.policy(reduceMotion: reduceMotion)
        ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .accessibilityLabel("Kanban error: \(message)")
                }

                board
            }
            .padding(20)

            if let card = model.selectedCardViewData {
                inspectorOverlay(for: card, policy: inspectorPolicy)
            }
        }
        // This stable container owns the transaction, so transitions animate for both insertion and removal.
        .animation(.easeOut(duration: inspectorPolicy.duration), value: model.selectedCardID)
        .background(OpsHubTerminalTheme.surfaceSecondary)
        .navigationTitle("Kanban")
        .sheet(isPresented: $model.isPresentingNewTask) {
            KanbanNewTaskSheet(model: model) {
                model.isPresentingNewTask = false
            }
        }
        .onExitCommand(perform: closeInspector)
        .onChange(of: model.selectedCardID) { previousID, currentID in
            focusedCardID = KanbanInspectorFocusRouter.target(
                previousCardID: previousID,
                selectedCardID: currentID,
                displayedCardIDs: Set(model.snapshot?.cards.map(\.id) ?? [])
            )
        }
        .onChange(of: model.isPresentingNewTask) { previousValue, currentValue in
            focusedHeaderControl = KanbanNewTaskFocusRouter.target(
                previousIsPresenting: previousValue,
                isPresenting: currentValue
            )
        }
        .task {
            await model.autoRefresh()
        }
    }

    private var header: some View {
        OpsHubFeatureHeader(
            eyebrow: "OPSHUB / KANBAN",
            title: "Kanban",
            metadata: model.headerMetadata
        ) {
            HStack(spacing: 8) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .frame(minHeight: KanbanControlLayout.headerHitTarget)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(model.isLoading)

                Button {
                    model.isPresentingNewTask = true
                } label: {
                    Label("New Task", systemImage: "plus")
                        .frame(minHeight: KanbanControlLayout.headerHitTarget)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityFocused($focusedHeaderControl, equals: .newTaskButton)
            }
            .buttonStyle(.plain)
            .opsHubTerminalControlGroup()
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            // Keep the finite set of columns in one stable layout transaction while their widths change.
            HStack(alignment: .top, spacing: 12) {
                ForEach(KanbanColumn.allCases) { column in
                    KanbanColumnView(
                        column: column,
                        cards: cards(in: column),
                        isCollapsed: collapsedColumns.contains(column),
                        selectedCardID: model.selectedCardID,
                        focusedCardID: $focusedCardID,
                        onToggleCollapsed: { toggle(column) },
                        onSelect: { card in
                            model.selectedCardID = card.id
                        }
                    )
                }
            }
            .animation(
                KanbanColumnCollapseAnimationPolicy.policy(reduceMotion: reduceMotion).animation,
                value: collapsedColumns
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
        .frame(maxHeight: .infinity)
        .accessibilityLabel("Kanban board")
        .overlay {
            if !model.isLoading, model.snapshot?.cards.isEmpty == true {
                ContentUnavailableView(
                    "No tasks yet",
                    systemImage: "checklist",
                    description: Text("Tasks will appear in their workflow column when they are added to the board."))
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .allowsHitTesting(false)
            }
        }
    }

    private func cards(in column: KanbanColumn) -> [KanbanCardViewData] {
        model.snapshot?.cards.filter { $0.column == column } ?? []
    }

    private func toggle(_ column: KanbanColumn) {
        let isCollapsed = columnPreferences.toggle(column: column)
        if isCollapsed {
            collapsedColumns.insert(column)
        } else {
            collapsedColumns.remove(column)
        }
    }

    private func inspectorOverlay(
        for card: KanbanCardViewData,
        policy: KanbanInspectorTransitionPolicy
    ) -> some View {
        return GeometryReader { proxy in
            let placement = KanbanInspectorLayout.placement(for: proxy.size.width)
            ZStack(alignment: .trailing) {
                KanbanInspectorBackdrop(onDismiss: closeInspector)

                KanbanTaskInspector(model: model, card: card, onClose: closeInspector)
                    .id(card.id)
                    .frame(width: placement.width)
                    .frame(maxHeight: .infinity)
                    .background(OpsHubTerminalTheme.surfacePrimary)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(OpsHubTerminalTheme.accent)
                            .frame(width: 2)
                    }
                    .padding(.trailing, placement.trailingInset)
            }
        }
        .transition(policy.transition)
        .zIndex(1)
    }

    private func closeInspector() {
        model.selectedCardID = nil
    }
}

enum KanbanControlLayout {
    static let headerHitTarget: CGFloat = 42
    static let collapseHitTarget: CGFloat = 34
}
