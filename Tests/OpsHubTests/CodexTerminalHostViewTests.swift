import AppKit
import XCTest
@testable import OpsHub

@MainActor
final class CodexTerminalHostViewTests: XCTestCase {
    func testTerminalUsesReadablePalette() {
        let host = SwiftTermCodexTerminalHost(
            startDirectory: FileManager.default.homeDirectoryForCurrentUser,
            configuration: CodexLaunchConfiguration()
        )

        XCTAssertEqual(host.terminalView.nativeBackgroundColor, .black)
        XCTAssertEqual(host.terminalView.nativeForegroundColor, .white)
        XCTAssertEqual(host.terminalView.caretColor, .white)
        XCTAssertEqual(host.terminalView.selectedTextBackgroundColor, .selectedContentBackgroundColor)
        XCTAssertEqual(host.terminalView.selectedTextForegroundColor, .white)
    }

    func testTerminalCanRestoreKeyboardFocus() {
        let host = SwiftTermCodexTerminalHost(
            startDirectory: FileManager.default.homeDirectoryForCurrentUser,
            configuration: CodexLaunchConfiguration()
        )
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 480), styleMask: [], backing: .buffered, defer: false)
        window.contentView = host.terminalView

        host.restoreKeyboardFocus()

        XCTAssertTrue(window.firstResponder === host.terminalView)
    }
}