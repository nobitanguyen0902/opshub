import Foundation

enum CodexTerminalSessionState: Equatable {
    case starting
    case running
    case terminating
    case exited(code: Int32?)
    case failed(message: String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .terminating:
            return true
        case .exited, .failed:
            return false
        }
    }

    var label: String {
        switch self {
        case .starting: return "Starting"
        case .running: return "Running"
        case .terminating: return "Stopping"
        case let .exited(code): return code.map { "Exited (\($0))" } ?? "Exited"
        case .failed: return "Failed"
        }
    }
}

struct CodexLaunchConfiguration: Equatable {
    let executable = "/bin/zsh"
    let arguments = ["-l"]
}

enum CodexTerminalTabColor: String, CaseIterable, Equatable {
    case `default`, red, orange, yellow, green, blue, purple, pink
}

@MainActor
protocol CodexTerminalHosting: AnyObject {
    var onStateChange: ((CodexTerminalSessionState) -> Void)? { get set }
    func terminate()
}

@MainActor
final class CodexTerminalSession: ObservableObject, Identifiable {
    let id: UUID
    @Published private(set) var title: String
    @Published private(set) var tabColor: CodexTerminalTabColor
    let host: any CodexTerminalHosting
    @Published var state: CodexTerminalSessionState

    init(
        id: UUID = UUID(),
        title: String,
        host: any CodexTerminalHosting,
        state: CodexTerminalSessionState = .starting,
        tabColor: CodexTerminalTabColor = .default
    ) {
        self.id = id
        self.title = title
        self.tabColor = tabColor
        self.host = host
        self.state = state
        host.onStateChange = { [weak self] state in self?.state = state }
    }

    func terminate() {
        guard state.isActive else { return }
        state = .terminating
        host.terminate()
    }

    func rename(to title: String) {
        self.title = title
    }

    func setTabColor(_ color: CodexTerminalTabColor) {
        tabColor = color
    }
}