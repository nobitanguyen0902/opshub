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

    @MainActor
    func testNewerLoadWinsWhenOlderRequestCompletesLast() async {
        let service = DeferredDevRoomMemberService()
        let viewModel = DevRoomMemberSelectionViewModel(
            service: service,
            initialSelectedUserIDs: []
        )

        let oldRequest = Task { await viewModel.loadMembers() }
        await service.waitForCallCount(1)

        let newRequest = Task { await viewModel.loadMembers() }
        await service.waitForCallCount(2)

        await service.complete(
            request: 1,
            with: [member(id: 20, username: "new", name: "New Connection")]
        )
        await newRequest.value

        await service.complete(
            request: 0,
            with: [member(id: 10, username: "old", name: "Old Connection")]
        )
        await oldRequest.value

        XCTAssertEqual(viewModel.members.map(\.id), [20])
        XCTAssertEqual(viewModel.loadState, .loaded)
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

private actor DeferredDevRoomMemberService: DevRoomMemberServicing {
    private var continuations: [CheckedContinuation<[DevRoomProjectMember], Never>] = []

    func projectMembers(projectPath: String) async throws -> [DevRoomProjectMember] {
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func waitForCallCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func complete(request: Int, with members: [DevRoomProjectMember]) {
        continuations[request].resume(returning: members)
    }
}

private enum MemberServiceError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "GitLab members are unavailable."
    }
}
