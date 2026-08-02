import Foundation

@MainActor
final class CodexTerminalViewModel: ObservableObject {
    @Published private(set) var sessions: [CodexTerminalSession] = []
    @Published var selectedSessionID: UUID?
    @Published var errorMessage: String?

    private let factory: any CodexTerminalSessionCreating
    private var nextSessionNumber = 1

    init(
        factory: any CodexTerminalSessionCreating = CodexTerminalSessionFactory()
    ) {
        self.factory = factory
    }

    @discardableResult
    func createSession() throws -> CodexTerminalSession {
        let session = try factory.makeSession(
            title: "Terminal \(nextSessionNumber)",
            startDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
        nextSessionNumber += 1
        sessions.append(session)
        selectedSessionID = session.id
        errorMessage = nil
        return session
    }

    func select(_ id: UUID) { selectedSessionID = id }

    func renameSession(_ id: UUID, to candidateTitle: String) {
        let title = candidateTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let session = sessions.first(where: { $0.id == id }) else { return }
        session.rename(to: title)
    }

    func requiresCloseConfirmation(_ id: UUID) -> Bool {
        sessions.first(where: { $0.id == id })?.state.isActive == true
    }

    func setColor(_ color: CodexTerminalTabColor, for id: UUID) {
        sessions.first(where: { $0.id == id })?.setTabColor(color)
    }

    func close(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].terminate()
        sessions.remove(at: index)
        if selectedSessionID == id {
            selectedSessionID = sessions.indices.contains(index) ? sessions[index].id : sessions.last?.id
        }
    }


    func terminateAll() {
        sessions.filter { $0.state.isActive }.forEach { $0.terminate() }
    }
}