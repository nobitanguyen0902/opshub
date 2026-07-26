import SwiftUI

struct CommandLogPanel: View {
    let logs: [String]
    let onClear: () -> Void

    @Binding private var isExpanded: Bool

    init(
        logs: [String],
        isExpanded: Binding<Bool>,
        onClear: @escaping () -> Void
    ) {
        self.logs = logs
        self.onClear = onClear
        _isExpanded = isExpanded
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ScrollView {
                    Text(logs.isEmpty ? "No command output yet." : logs.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(logs.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(12)
                }
                .frame(minHeight: 100, maxHeight: 240)
                .opsHubTerminalSurface(cornerRadius: OpsHubTerminalTheme.controlRadius)

                HStack {
                    Spacer()
                    Button("Clear", role: .destructive, action: onClear)
                        .buttonStyle(.plain)
                        .opsHubTerminalControl()
                        .disabled(logs.isEmpty)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("COMMAND LOG", systemImage: "terminal")
                .font(.system(.callout, design: .monospaced).weight(.semibold))
                .foregroundStyle(OpsHubTerminalTheme.accent)
        }
    }
}

#Preview {
    CommandLogPanelPreview()
}

private struct CommandLogPanelPreview: View {
    @State private var isExpanded = true

    var body: some View {
        CommandLogPanel(
            logs: ["$ brew update", "Already up-to-date."],
            isExpanded: $isExpanded,
            onClear: {}
        )
        .padding()
    }
}
