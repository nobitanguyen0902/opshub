import SwiftUI

struct KanbanView: View {
    @StateObject private var model: KanbanViewModel
    @State private var collapsedColumns: Set<KanbanColumn>

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
        .background(OpsHubTerminalTheme.surfaceSecondary)
        .navigationTitle("Kanban")
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
            }
            .buttonStyle(.plain)
            .opsHubTerminalControlGroup()
        }
    }

    private var board: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(KanbanColumn.allCases) { column in
                    KanbanColumnView(
                        column: column,
                        cards: cards(in: column),
                        isCollapsed: collapsedColumns.contains(column),
                        selectedCardID: model.selectedCardID,
                        onToggleCollapsed: { toggle(column) },
                        onSelect: { card in
                            model.selectedCardID = card.id
                        }
                    )
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 1)
        }
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
}

enum KanbanControlLayout {
    static let headerHitTarget: CGFloat = 42
    static let collapseHitTarget: CGFloat = 34
}
