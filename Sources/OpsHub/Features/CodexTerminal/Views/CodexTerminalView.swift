import SwiftUI

struct CodexTerminalView: View {
    @ObservedObject var viewModel: CodexTerminalViewModel
    @State private var pendingCloseID: UUID?
    @State private var pendingRenameID: UUID?
    @State private var renameDraft = ""

    var body: some View {
        VStack(spacing: 12) {
            OpsHubFeatureHeader(eyebrow: "OPSHUB / TERMINAL", title: "Terminal", metadata: metadata) {
                Button("New Terminal", systemImage: "plus") { createSession() }
                .buttonStyle(.plain)
                .opsHubTerminalControl()
            }

            if let message = viewModel.errorMessage {
                Text(message).font(.system(.caption, design: .monospaced)).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.sessions.isEmpty {
                ContentUnavailableView("No terminals", systemImage: "terminal", description: Text("Select New Terminal to open a login shell at your home directory."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tabStrip
                terminalStack
            }
        }
        .padding(16)
        .confirmationDialog("Terminate this terminal session?", isPresented: closeConfirmationBinding) {
            Button("Terminate and Close", role: .destructive) {
                if let pendingCloseID { viewModel.close(pendingCloseID) }
                pendingCloseID = nil
            }
            Button("Cancel", role: .cancel) { pendingCloseID = nil }
        } message: { Text("Closing a running tab can interrupt work in progress.") }
        .alert("Rename Tab", isPresented: renameAlertBinding) {
            TextField("Tab Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { resetRenameState() }
            Button("Rename") { submitRename() }
                .disabled(normalizedRenameDraft.isEmpty)
        }
    }

    private var metadata: String {
        "login shell · home directory · sessions=\(viewModel.sessions.count)"
    }

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(viewModel.sessions) { session in
                    CodexTerminalTab(
                        session: session,
                        isSelected: viewModel.selectedSessionID == session.id,
                        onSelect: { viewModel.select(session.id) },
                        onClose: { requestClose(session) },
                        onRename: { requestRename(session) }
                    )
                }
            }
        }.opsHubTerminalSurface()
    }

    private var terminalStack: some View {
        ZStack {
            ForEach(viewModel.sessions) { session in
                if let host = session.host as? SwiftTermCodexTerminalHost {
                    CodexTerminalHostView(
                        host: host,
                        isActive: viewModel.selectedSessionID == session.id
                    )
                        .opacity(viewModel.selectedSessionID == session.id ? 1 : 0)
                        .allowsHitTesting(viewModel.selectedSessionID == session.id)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: OpsHubTerminalTheme.containerRadius))
        .overlay { RoundedRectangle(cornerRadius: OpsHubTerminalTheme.containerRadius).strokeBorder(OpsHubTerminalTheme.borderStrong) }
    }

    private var closeConfirmationBinding: Binding<Bool> {
        Binding(get: { pendingCloseID != nil }, set: { if !$0 { pendingCloseID = nil } })
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(get: { pendingRenameID != nil }, set: { if !$0 { resetRenameState() } })
    }

    private var normalizedRenameDraft: String {
        renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func requestClose(_ session: CodexTerminalSession) {
        if viewModel.requiresCloseConfirmation(session.id) { pendingCloseID = session.id } else { viewModel.close(session.id) }
    }

    private func requestRename(_ session: CodexTerminalSession) {
        pendingRenameID = session.id
        renameDraft = session.title
    }

    private func submitRename() {
        if let pendingRenameID { viewModel.renameSession(pendingRenameID, to: renameDraft) }
        resetRenameState()
    }

    private func resetRenameState() {
        pendingRenameID = nil
        renameDraft = ""
    }

    private func createSession() {
        do { try viewModel.createSession() } catch { viewModel.errorMessage = error.localizedDescription }
    }

}

private struct CodexTerminalTab: View {
    @ObservedObject var session: CodexTerminalSession
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            Button(action: onSelect) {
                HStack(spacing: 7) {
                    Circle().fill(session.tabColor.color ?? (session.state.isActive ? OpsHubTerminalTheme.accent : Color.secondary)).frame(width: 7, height: 7)
                    Text(session.title)
                    Text(session.state.label).foregroundStyle(.secondary)
                }
            }.buttonStyle(.plain)
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Close \(session.title)")
        }
        .padding(.horizontal, 10).frame(minHeight: 34)
        .background(isSelected ? OpsHubTerminalTheme.selected : .clear)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename Tab", action: onRename)
            Menu("Tab Color") {
                ForEach(CodexTerminalTabColor.allCases, id: \.self) { color in
                    Button(color.rawValue.capitalized) { session.setTabColor(color) }
                }
            }
        }
        .accessibilityLabel("\(session.title), \(session.state.label)")
    }
}

private extension CodexTerminalTabColor {
    var color: Color? {
        switch self {
        case .default: nil
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}