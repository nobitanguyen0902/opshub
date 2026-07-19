import Foundation
import XCTest
@testable import OpsHub

final class DevRoomMemberSelectionViewModelTests: XCTestCase {
    @MainActor
    func testLoadKeepsSavedSelectionAndFiltersByNameOrUsername() async {
        let service = StubDevRoomMemberService(members: [
            member(id: 10, username: "alice", name: "Alice Nguyen"),
            member(id: 20, username: "bob", name: "Bob Tran")
        ])
        let viewModel = DevRoomMemberSelectionViewModel(
            service: service,
            initialSelectedUserIDs: [20]
        )

        await viewModel.loadMembers()
        viewModel.searchText = "alice"

        XCTAssertEqual(viewModel.filteredMembers.map(\.id), [10])
        XCTAssertEqual(viewModel.draftSelectedUserIDs, [20])
        XCTAssertTrue(viewModel.hasLoadedMembers)
    }

    @MainActor
    func testNewlyLoadedMembersRemainUnselectedUntilAddedToDraft() async {
        let service = StubDevRoomMemberService(members: [
            member(id: 10, username: "alice", name: "Alice Nguyen"),
            member(id: 20, username: "bob", name: "Bob Tran")
        ])
        let viewModel = DevRoomMemberSelectionViewModel(
            service: service,
            initialSelectedUserIDs: [20]
        )

        await viewModel.loadMembers()

        XCTAssertFalse(viewModel.draftSelectedUserIDs.contains(10))
        XCTAssertTrue(viewModel.draftSelectedUserIDs.contains(20))
    }

    @MainActor
    func testFailedLoadDoesNotReplaceSavedDraftWithEmptySelection() async {
        let viewModel = DevRoomMemberSelectionViewModel(
            service: FailingDevRoomMemberService(),
            initialSelectedUserIDs: [20]
        )

        await viewModel.loadMembers()

        XCTAssertEqual(viewModel.draftSelectedUserIDs, [20])
        XCTAssertFalse(viewModel.hasLoadedMembers)
        guard case .failed = viewModel.loadState else {
            return XCTFail("Expected failed member load")
        }
    }

    @MainActor
    func testSelectAllAndClearOnlyChangeDraftSelection() async {
        let service = StubDevRoomMemberService(members: [
            member(id: 10, username: "alice", name: "Alice Nguyen"),
            member(id: 20, username: "bob", name: "Bob Tran")
        ])
        let viewModel = DevRoomMemberSelectionViewModel(
            service: service,
            initialSelectedUserIDs: [20]
        )
        await viewModel.loadMembers()

        viewModel.selectAll()
        XCTAssertEqual(viewModel.draftSelectedUserIDs, [10, 20])

        viewModel.clear()
        XCTAssertEqual(viewModel.draftSelectedUserIDs, [])
    }
}

private func member(id: Int, username: String, name: String) -> DevRoomProjectMember {
    DevRoomProjectMember(
        id: id,
        username: username,
        name: name,
        avatarURL: nil,
        accessLevel: 30
    )
}

private actor StubDevRoomMemberService: DevRoomMemberServicing {
    let members: [DevRoomProjectMember]

    init(members: [DevRoomProjectMember]) {
        self.members = members
    }

    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        members
    }
}

private actor FailingDevRoomMemberService: DevRoomMemberServicing {
    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        throw MemberServiceError.unavailable
    }
}

private enum MemberServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "GitLab members are unavailable."
    }
}
