import SwiftUI

struct SettingsView: View {
    @State private var gitLabURL = ""
    @State private var personalAccessToken = ""
    @State private var isTokenVisible = false
    @State private var connectionStatus: ConnectionStatus = .notTested
    @State private var lastSavedAt: Date?

    private var canTestConnection: Bool {
        !gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("GitLab") {
                TextField("GitLab URL", text: $gitLabURL, prompt: Text("https://gitlab.com"))
                    .textContentType(.URL)
                    .autocorrectionDisabled()

                tokenField
            }

            Section {
                HStack {
                    Button {
                        saveSettings()
                    } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        testConnection()
                    } label: {
                        Label("Test Connection", systemImage: "network")
                    }
                    .disabled(!canTestConnection)
                }
            }

            Section("Connection Status") {
                ConnectionStatusCard(
                    status: connectionStatus,
                    gitLabURL: normalizedGitLabURL,
                    lastSavedAt: lastSavedAt
                )
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if isTokenVisible {
                    TextField("Personal Access Token", text: $personalAccessToken)
                } else {
                    SecureField("Personal Access Token", text: $personalAccessToken)
                }
            }
            .textContentType(.password)
            .autocorrectionDisabled()

            Button {
                isTokenVisible.toggle()
            } label: {
                Label(isTokenVisible ? "Hide" : "Show", systemImage: isTokenVisible ? "eye.slash" : "eye")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help(isTokenVisible ? "Hide token" : "Show token")
        }
    }

    private var normalizedGitLabURL: String {
        gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func saveSettings() {
        lastSavedAt = .now
        connectionStatus = .savedLocally
    }

    private func testConnection() {
        guard let url = URL(string: normalizedGitLabURL), url.scheme != nil, url.host != nil else {
            connectionStatus = .invalidURL
            return
        }

        connectionStatus = .readyToConnect
    }
}

private struct ConnectionStatusCard: View {
    let status: ConnectionStatus
    let gitLabURL: String
    let lastSavedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.systemImage)
                    .font(.title3)
                    .foregroundStyle(status.tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(status.title)
                        .font(.headline)

                    Text(status.message(gitLabURL: gitLabURL, lastSavedAt: lastSavedAt))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private enum ConnectionStatus: Equatable {
    case notTested
    case savedLocally
    case invalidURL
    case readyToConnect

    var title: String {
        switch self {
        case .notTested:
            "Not tested"
        case .savedLocally:
            "Saved for this session"
        case .invalidURL:
            "Invalid GitLab URL"
        case .readyToConnect:
            "Ready to connect"
        }
    }

    var systemImage: String {
        switch self {
        case .notTested:
            "circle.dashed"
        case .savedLocally:
            "checkmark.circle"
        case .invalidURL:
            "exclamationmark.triangle"
        case .readyToConnect:
            "checkmark.seal"
        }
    }

    var tint: Color {
        switch self {
        case .notTested:
            .secondary
        case .savedLocally, .readyToConnect:
            .green
        case .invalidURL:
            .orange
        }
    }

    func message(gitLabURL: String, lastSavedAt: Date?) -> String {
        switch self {
        case .notTested:
            return "Enter your GitLab URL and personal access token, then test the connection."
        case .savedLocally:
            guard let lastSavedAt else {
                return "Settings are held in memory until persistence is added."
            }

            return "Settings saved at \(lastSavedAt.formatted(date: .omitted, time: .shortened)). Persistence is not enabled yet."
        case .invalidURL:
            return "Use a full URL such as https://gitlab.com or your self-managed GitLab host."
        case .readyToConnect:
            return "Configuration looks valid for \(gitLabURL). Live API verification is not wired yet."
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
