import AppKit
@preconcurrency import SwiftTerm
import SwiftUI

@MainActor
final class SwiftTermCodexTerminalHost: NSObject, CodexTerminalHosting {
    let terminalView = LocalProcessTerminalView(frame: .zero)
    var onStateChange: ((CodexTerminalSessionState) -> Void)?
    private var didStart = false
    private let startDirectory: URL
    private let configuration: CodexLaunchConfiguration

    init(startDirectory: URL, configuration: CodexLaunchConfiguration) {
        self.startDirectory = startDirectory
        self.configuration = configuration
        super.init()
        terminalView.processDelegate = self
        terminalView.nativeBackgroundColor = .textBackgroundColor
        terminalView.nativeForegroundColor = .textColor
        terminalView.caretColor = .systemGreen
    }

    func startIfNeeded() {
        guard !didStart else { return }
        didStart = true
        terminalView.startProcess(
            executable: configuration.executable,
            args: configuration.arguments,
            currentDirectory: startDirectory.path
        )
        onStateChange?(.running)
        DispatchQueue.main.async { [weak self] in
            guard let terminalView = self?.terminalView else { return }
            terminalView.window?.makeFirstResponder(terminalView)
        }
    }

    func terminate() { terminalView.terminate() }
}

extension SwiftTermCodexTerminalHost: @preconcurrency LocalProcessTerminalViewDelegate {
    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) { onStateChange?(.exited(code: exitCode)) }
}

struct CodexTerminalHostView: NSViewRepresentable {
    let host: SwiftTermCodexTerminalHost

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        host.startIfNeeded()
        return host.terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}
}