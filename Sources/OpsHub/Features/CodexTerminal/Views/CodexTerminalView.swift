import SwiftUI

struct CodexTerminalView: View {
    @ObservedObject var viewModel: CodexTerminalViewModel
    @State private var pendingCloseID: UUID?

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
    }

    private var metadata: String {
        "login shell · home directory · sessions=\(viewModel.sessions.count)"
    }

    private var tabStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(viewModel.sessions) { session in
                    HStack(spacing: 7) {
                        Button { viewModel.select(session.id) } label: {
                            HStack(spacing: 7) {
                                Circle().fill(session.state.isActive ? OpsHubTerminalTheme.accent : Color.secondary).frame(width: 7, height: 7)
                                Text(session.title)
                                Text(session.state.label).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Button { requestClose(session) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).accessibilityLabel("Close \(session.title)")
                    }
                    .padding(.horizontal, 10).frame(minHeight: 34)
                    .background(viewModel.selectedSessionID == session.id ? OpsHubTerminalTheme.selected : .clear)
                    .accessibilityLabel("\(session.title), \(session.state.label)")
                }
            }
        }.opsHubTerminalSurface()
    }

    private var terminalStack: some View {
        ZStack {
            ForEach(viewModel.sessions) { session in
                if let host = session.host as? SwiftTermCodexTerminalHost {
                    CodexTerminalHostView(host: host)
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

    private func requestClose(_ session: CodexTerminalSession) {
        if viewModel.requiresCloseConfirmation(session.id) { pendingCloseID = session.id } else { viewModel.close(session.id) }
    }

    private func createSession() {
        do { try viewModel.createSession() } catch { viewModel.errorMessage = error.localizedDescription }
    }

}