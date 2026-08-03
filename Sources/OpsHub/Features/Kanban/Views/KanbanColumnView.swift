import SwiftUI

enum KanbanColumnLayout {
    static func width(isCollapsed: Bool) -> CGFloat {
        isCollapsed ? 48 : 264
    }
}

struct KanbanColumnView: View {
    let column: KanbanColumn
    let cards: [KanbanCardViewData]
    let isCollapsed: Bool
    let selectedCardID: KanbanCardID?
    let onToggleCollapsed: () -> Void
    let onSelect: (KanbanCardViewData) -> Void

    var body: some View {
        Group {
            if isCollapsed {
                collapsedColumn
            } else {
                expandedColumn
            }
        }
        .frame(width: KanbanColumnLayout.width(isCollapsed: isCollapsed), alignment: .topLeading)
        .animation(.default, value: isCollapsed)
    }

    private var collapsedColumn: some View {
        Button(action: onToggleCollapsed) {
            VStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                Text(column.title.uppercased())
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .rotationEffect(.degrees(-90))
                    .fixedSize()
                    .frame(height: 92)
                Text("\(cards.count)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(column.indicatorColor.opacity(0.16), in: Capsule())
            }
            .frame(maxWidth: .infinity, minHeight: 188, alignment: .top)
            .foregroundStyle(column.indicatorColor)
            .padding(.vertical, 12)
            .background(OpsHubTerminalTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(column.indicatorColor.opacity(0.58))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(column.title), \(cards.count) tasks, collapsed")
        .accessibilityHint("Double-click to expand this column")
    }

    private var expandedColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(column.title, systemImage: column.systemImage)
                    .font(.system(.headline, design: .monospaced).weight(.bold))
                    .foregroundStyle(column.indicatorColor)

                Text("\(cards.count)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                Button(action: onToggleCollapsed) {
                    Image(systemName: "rectangle.compress.vertical")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Collapse \(column.title) column")
            }

            if cards.isEmpty {
                Text("No tasks")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
            } else {
                VStack(spacing: 8) {
                    ForEach(cards) { card in
                        KanbanCardView(
                            card: card,
                            isSelected: selectedCardID == card.id,
                            onSelect: { onSelect(card) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(OpsHubTerminalTheme.surfacePrimary, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(OpsHubTerminalTheme.borderSubtle)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.title) column, \(cards.count) tasks")
    }
}

private struct KanbanCardView: View {
    let card: KanbanCardViewData
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Label(card.priority.title, systemImage: prioritySymbol)
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(priorityColor)

                    Spacer(minLength: 4)

                    Text(card.isWorkflowOwned ? "WORKFLOW" : "EXTERNAL")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(.secondary)
                }

                Text(card.title)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                Text(card.displayID)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Divider()

                if let stageLabel = card.stageLabel, !stageLabel.isEmpty {
                    Label(stageLabel, systemImage: "person.crop.circle")
                        .lineLimit(1)
                }

                if let elapsed = card.elapsed {
                    Label(formattedElapsed(elapsed), systemImage: "clock")
                }

                if let workspaceName = card.workspaceName, !workspaceName.isEmpty {
                    Label(workspaceName, systemImage: "folder")
                        .lineLimit(1)
                }
            }
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? OpsHubTerminalTheme.selected : OpsHubTerminalTheme.surfaceSecondary)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? OpsHubTerminalTheme.borderStrong : OpsHubTerminalTheme.borderSubtle)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cardAccessibilityLabel)
        .accessibilityHint("Select to inspect this task")
    }

    private var prioritySymbol: String {
        switch card.priority {
        case .low: "arrow.down"
        case .normal: "minus"
        case .high: "arrow.up"
        case .urgent: "exclamationmark.2"
        }
    }

    private var priorityColor: Color {
        switch card.priority {
        case .low: .secondary
        case .normal: OpsHubTerminalTheme.accent
        case .high: .orange
        case .urgent: .red
        }
    }

    private var cardAccessibilityLabel: String {
        var values = [card.priority.title, card.isWorkflowOwned ? "workflow" : "external task", card.title, card.displayID]
        if let stageLabel = card.stageLabel { values.append(stageLabel) }
        if let elapsed = card.elapsed { values.append(formattedElapsed(elapsed)) }
        if let workspaceName = card.workspaceName { values.append(workspaceName) }
        return values.joined(separator: ", ")
    }

    private func formattedElapsed(_ elapsed: TimeInterval) -> String {
        let totalSeconds = max(0, Int(elapsed))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

private extension KanbanColumn {
    var title: String {
        rawValue.capitalized
    }

    var systemImage: String {
        switch self {
        case .triage: "tray"
        case .todo: "list.bullet"
        case .ready: "checkmark.circle"
        case .running: "play.circle"
        case .blocked: "exclamationmark.triangle"
        case .done: "checkmark.seal"
        }
    }

    var indicatorColor: Color {
        switch self {
        case .triage: .yellow
        case .todo: .secondary
        case .ready: OpsHubTerminalTheme.accent
        case .running: .blue
        case .blocked: .orange
        case .done: .green
        }
    }
}
