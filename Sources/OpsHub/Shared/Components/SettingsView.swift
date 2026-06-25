import SwiftUI

struct SettingsView: View {
    private let settingsStore: any GitLabSettingsStoring
    private let gitLabService: any GitLabServicing

    @State private var gitLabURL = ""
    @State private var personalAccessToken = ""
    @State private var isTokenVisible = false
    @State private var connectionStatus: ConnectionStatus = .notTested
    @State private var isTestingConnection = false
    @State private var lastSavedAt: Date?

    init(
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore(),
        gitLabService: any GitLabServicing = GitLabMockService()
    ) {
        self.settingsStore = settingsStore
        self.gitLabService = gitLabService

        let settings = settingsStore.load()
        _gitLabURL = State(initialValue: settings.gitLabURL)
        _personalAccessToken = State(initialValue: settings.personalAccessToken)
    }

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
                        Task { await testConnection() }
                    } label: {
                        if isTestingConnection {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                    }
                    .disabled(!canTestConnection || isTestingConnection)
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
        .animation(.smooth(duration: 0.2), value: isTestingConnection)
        .animation(.smooth(duration: 0.2), value: connectionStatus)
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
        do {
            try settingsStore.save(
                GitLabSettings(
                    gitLabURL: normalizedGitLabURL,
                    personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            lastSavedAt = .now
            connectionStatus = .savedLocally
        } catch {
            connectionStatus = .saveFailed(error.localizedDescription)
        }
    }

    private func testConnection() async {
        guard let url = URL(string: normalizedGitLabURL), url.scheme != nil, url.host != nil else {
            connectionStatus = .invalidURL
            return
        }

        let settings = GitLabSettings(
            gitLabURL: normalizedGitLabURL,
            personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        isTestingConnection = true
        connectionStatus = .testing
        defer { isTestingConnection = false }

        do {
            connectionStatus = .testResult(try await gitLabService.testConnection(settings: settings))
        } catch {
            connectionStatus = .timeout
        }
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
    case testing
    case testResult(GitLabConnectionTestResult)
    case timeout
    case saveFailed(String)

    var title: String {
        switch self {
        case .notTested:
            "Not tested"
        case .savedLocally:
            "Saved"
        case .invalidURL:
            "Invalid GitLab URL"
        case .testing:
            "Testing connection"
        case .testResult(.connected):
            "Connected"
        case .testResult(.unauthorized):
            "Unauthorized"
        case .testResult(.timeout), .timeout:
            "Timed out"
        case .saveFailed:
            "Could not save settings"
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
        case .testing:
            "network"
        case .testResult(.connected):
            "checkmark.seal"
        case .testResult(.unauthorized):
            "lock.trianglebadge.exclamationmark"
        case .testResult(.timeout), .timeout:
            "clock.badge.exclamationmark"
        case .saveFailed:
            "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .notTested:
            .secondary
        case .savedLocally, .testResult(.connected):
            .green
        case .testing:
            .blue
        case .invalidURL, .testResult(.unauthorized), .testResult(.timeout), .timeout, .saveFailed:
            .orange
        }
    }

    func message(gitLabURL: String, lastSavedAt: Date?) -> String {
        switch self {
        case .notTested:
            return "Enter your GitLab URL and personal access token, then test the connection."
        case .savedLocally:
            guard let lastSavedAt else {
                return "GitLab URL is stored in UserDefaults. Personal access token is stored in Keychain."
            }

            return "Settings saved at \(lastSavedAt.formatted(date: .omitted, time: .shortened)). Token is stored in Keychain."
        case .invalidURL:
            return "Use a full URL such as https://gitlab.com or your self-managed GitLab host."
        case .testing:
            return "Checking \(gitLabURL) with the local GitLab mock service."
        case .testResult(.connected):
            return "Mock connection succeeded for \(gitLabURL). No real GitLab API was called."
        case .testResult(.unauthorized):
            return "Mock connection rejected the token for \(gitLabURL). Check the saved token value."
        case .testResult(.timeout), .timeout:
            return "Mock connection timed out for \(gitLabURL). Try testing again."
        case let .saveFailed(message):
            return message
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
