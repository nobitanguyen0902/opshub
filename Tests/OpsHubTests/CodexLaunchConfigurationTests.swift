import XCTest
@testable import OpsHub

final class CodexLaunchConfigurationTests: XCTestCase {
    func testDefaultConfigurationStartsLoginShellWithoutAgentCommand() {
        let configuration = CodexLaunchConfiguration()

        XCTAssertEqual(configuration.executable, "/bin/zsh")
        XCTAssertEqual(configuration.arguments, ["-l"])
    }
}