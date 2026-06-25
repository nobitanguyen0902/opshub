import XCTest
@testable import OpsHub

final class GitLabMockServiceTests: XCTestCase {
    func testConnectionUsesInjectedMockResult() async throws {
        let service = GitLabMockService(
            networkDelay: .zero,
            connectionResultProvider: { .unauthorized }
        )

        let result = try await service.testConnection(
            settings: GitLabSettings(
                gitLabURL: "https://gitlab.example.com",
                personalAccessToken: "token"
            )
        )

        XCTAssertEqual(result, .unauthorized)
    }
}
