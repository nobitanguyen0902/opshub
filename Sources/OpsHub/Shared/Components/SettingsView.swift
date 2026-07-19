import AppKit
import SwiftUI

struct SettingsView: View {
    private let settingsStore: any GitLabSettingsStoring
    private let gitLabService: any GitLabServicing
    private let visibilityStore: any DevRoomVisibilitySettingsStoring
    private let onDevRoomVisibilitySaved: (Set<Int>) -> Void

    @State private var gitLabURL = ""
    @State private var personalAccessToken = ""
    @State private var isTokenVisible = false
    @State private var connectionStatus: ConnectionStatus = .notTested
    @State private var isTestingConnection = false
    @State private var lastSavedAt: Date?
    @StateObject private var memberSelectionViewModel: DevRoomMemberSelectionViewModel

    init(
        settingsStore: any GitLabSettingsStoring = GitLabSettingsStore(),
        gitLabService: any GitLabServicing = GitLabService(),
        visibilityStore: any DevRoomVisibilitySettingsStoring = DevRoomVisibilitySettingsStore(),
        memberService: any DevRoomMemberServicing = GitLabService(),
        onDevRoomVisibilitySaved: @escaping (Set<Int>) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.gitLabService = gitLabService
        self.visibilityStore = visibilityStore
        self.onDevRoomVisibilitySaved = onDevRoomVisibilitySaved

        let settings = settingsStore.load()
        _gitLabURL = State(initialValue: settings.gitLabURL)
        _personalAccessToken = State(initialValue: settings.personalAccessToken)
        _connectionStatus = State(initialValue: Self.initialConnectionStatus(from: settings))
        _lastSavedAt = State(initialValue: settings.lastConnectionTestedAt)
        _memberSelectionViewModel = StateObject(
            wrappedValue: DevRoomMemberSelectionViewModel(
                service: memberService,
                initialSelectedUserIDs: visibilityStore.load().selectedUserIDs
            )
        )
    }

    private var canTestConnection: Bool {
        !gitLabURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("GitLab")
                        .font(.headline)

                    EditableSettingsTextField(
                        placeholder: "https://gitlab.com",
                        text: $gitLabURL
                    )

                    tokenField
                }

                DevRoomMemberSelectionSection(viewModel: memberSelectionViewModel)

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
                            LoadingSpinnerView()
                        } else {
                            Label("Test Connection", systemImage: "network")
                        }
                    }
                    .disabled(!canTestConnection || isTestingConnection)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Connection Status")
                        .font(.headline)

                    ConnectionStatusCard(
                        status: connectionStatus,
                        gitLabURL: normalizedGitLabURL,
                        lastSavedAt: lastSavedAt
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Settings")
        .animation(.smooth(duration: 0.2), value: isTestingConnection)
        .animation(.smooth(duration: 0.2), value: connectionStatus)
        .task {
            await memberSelectionViewModel.loadMembers()
        }
    }

    private var tokenField: some View {
        HStack(spacing: 8) {
            Group {
                if isTokenVisible {
                    EditableSettingsTextField(
                        placeholder: "Personal Access Token",
                        text: $personalAccessToken
                    )
                } else {
                    EditableSettingsTextField(
                        placeholder: "Personal Access Token",
                        text: $personalAccessToken,
                        isSecure: true
                    )
                }
            }
            .id(isTokenVisible)

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

    private static func initialConnectionStatus(from settings: GitLabSettings) -> ConnectionStatus {
        guard let lastConnectionTestResult = settings.lastConnectionTestResult else {
            return .notTested
        }

        return .testResult(lastConnectionTestResult)
    }

    private func saveSettings() {
        do {
            let settings = GitLabSettings(
                gitLabURL: normalizedGitLabURL,
                personalAccessToken: personalAccessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                lastConnectionTestResult: nil,
                lastConnectionTestedAt: nil
            )
            let outcome = try SettingsSaveIntegration.save(
                gitLabSettings: settings,
                settingsStore: settingsStore,
                visibilityStore: visibilityStore,
                memberSelectionViewModel: memberSelectionViewModel,
                onDevRoomVisibilitySaved: onDevRoomVisibilitySaved
            )
            lastSavedAt = .now
            connectionStatus = outcome == .allSettingsSaved
                ? .savedLocally
                : .gitLabSavedMemberSelectionUnchanged
            Task { await memberSelectionViewModel.loadMembers() }
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
            let result = try await gitLabService.testConnection(settings: settings)
            let testedAt = Date.now
            try settingsStore.save(
                GitLabSettings(
                    gitLabURL: settings.gitLabURL,
                    personalAccessToken: settings.personalAccessToken,
                    lastConnectionTestResult: result,
                    lastConnectionTestedAt: testedAt
                )
            )
            lastSavedAt = testedAt
            connectionStatus = .testResult(result)
        } catch let error as GitLabSettingsStoreError {
            connectionStatus = .saveFailed(error.localizedDescription)
        } catch {
            connectionStatus = .timeout
        }
    }
}

@MainActor
enum SettingsSaveIntegration {
    enum Outcome: Equatable {
        case allSettingsSaved
        case gitLabSettingsSavedOnly
    }

    @discardableResult
    static func save(
        gitLabSettings: GitLabSettings,
        settingsStore: any GitLabSettingsStoring,
        visibilityStore: any DevRoomVisibilitySettingsStoring,
        memberSelectionViewModel: DevRoomMemberSelectionViewModel,
        onDevRoomVisibilitySaved: (Set<Int>) -> Void
    ) throws -> Outcome {
        try settingsStore.save(gitLabSettings)

        guard memberSelectionViewModel.hasLoadedMembers else {
            return .gitLabSettingsSavedOnly
        }

        let ids = memberSelectionViewModel.draftSelectedUserIDs
        visibilityStore.save(DevRoomVisibilitySettings(selectedUserIDs: ids))
        onDevRoomVisibilitySaved(ids)
        memberSelectionViewModel.markSaved(ids)
        return .allSettingsSaved
    }
}

private struct EditableSettingsTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    var isSecure = false

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = isSecure ? NSSecureTextField() : NSTextField()
        textField.placeholderString = placeholder
        textField.stringValue = text
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.drawsBackground = true
        textField.controlSize = .regular
        textField.delegate = context.coordinator
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        if textField.stringValue != text {
            textField.stringValue = text
        }

        textField.placeholderString = placeholder
        textField.isEditable = true
        textField.isSelectable = true
        textField.isEnabled = true
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else {
                return
            }

            text = textField.stringValue
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
    case gitLabSavedMemberSelectionUnchanged
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
        case .gitLabSavedMemberSelectionUnchanged:
            "GitLab settings saved"
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
        case .gitLabSavedMemberSelectionUnchanged:
            "exclamationmark.triangle"
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
        case .gitLabSavedMemberSelectionUnchanged,
             .invalidURL,
             .testResult(.unauthorized),
             .testResult(.timeout),
             .timeout,
             .saveFailed:
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
        case .gitLabSavedMemberSelectionUnchanged:
            return "GitLab settings were saved, but Dev Room members stayed unchanged because the member list is not available yet."
        case .invalidURL:
            return "Use a full URL such as https://gitlab.com or your self-managed GitLab host."
        case .testing:
            return "Checking \(gitLabURL) with the GitLab API."
        case .testResult(.connected):
            return "Connection succeeded for \(gitLabURL)."
        case .testResult(.unauthorized):
            return "GitLab rejected the token for \(gitLabURL). Check the saved token value."
        case .testResult(.timeout), .timeout:
            return "GitLab connection timed out for \(gitLabURL). Try testing again."
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
