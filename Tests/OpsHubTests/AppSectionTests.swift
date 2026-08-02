import XCTest
@testable import OpsHub

final class AppSectionTests: XCTestCase {
    func testNavigationDefaultsToDashboard() {
        XCTAssertEqual(AppNavigationState().selection, .dashboard)
    }

    func testTerminalAppearsBeforeSettingsWithoutRemovingExistingSections() {
        XCTAssertEqual(
            AppSection.allCases,
            [.dashboard, .devRoom, .brew, .gitLab, .terminal, .settings]
        )
        XCTAssertEqual(AppSection.terminal.title, "Terminal")
        XCTAssertEqual(AppSection.terminal.systemImage, "terminal")
    }

    @MainActor
    func testContentViewAcceptsSharedDevRoomVisibilityDependencies() {
        let visibilityStore = AppSectionVisibilityStore(selectedUserIDs: [10])
        let memberService = AppSectionMemberService()
        let devRoomViewModel = DevRoomViewModel(
            service: AppSectionDevRoomService(),
            selectedUserIDs: visibilityStore.load().selectedUserIDs
        )

        XCTAssertNoThrow(
            ContentView(
                navigationState: AppNavigationState(),
                settingsStore: AppSectionGitLabSettingsStore(),
                visibilityStore: visibilityStore,
                devRoomViewModel: devRoomViewModel,
                memberService: memberService
            )
        )

        XCTAssertEqual(devRoomViewModel.selectedUserIDs, [10])
    }
}

private struct AppSectionGitLabSettingsStore: GitLabSettingsStoring {
    func load() -> GitLabSettings {
        GitLabSettings(gitLabURL: "", personalAccessToken: "")
    }

    func save(_ settings: GitLabSettings) throws {}
}

private struct AppSectionVisibilityStore: DevRoomVisibilitySettingsStoring {
    let selectedUserIDs: Set<Int>

    func load() -> DevRoomVisibilitySettings {
        DevRoomVisibilitySettings(selectedUserIDs: selectedUserIDs)
    }

    func save(_ settings: DevRoomVisibilitySettings) {}
}

private actor AppSectionMemberService: DevRoomMemberServicing {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        []
    }
}

private actor AppSectionDevRoomService: DevRoomServicing {
    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        []
    }
}
