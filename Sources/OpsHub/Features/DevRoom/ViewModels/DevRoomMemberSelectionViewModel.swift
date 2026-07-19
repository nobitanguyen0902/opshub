import Foundation

enum DevRoomMemberLoadState: Equatable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

@MainActor
final class DevRoomMemberSelectionViewModel: ObservableObject {
    @Published private(set) var members: [DevRoomProjectMember] = []
    @Published private(set) var loadState: DevRoomMemberLoadState = .idle
    @Published var searchText = ""
    @Published private(set) var draftSelectedUserIDs: Set<Int>

    private let service: any DevRoomMemberServicing

    var hasLoadedMembers: Bool {
        loadState == .loaded || loadState == .empty
    }

    var filteredMembers: [DevRoomProjectMember] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return members
        }

        return members.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
                $0.username.localizedCaseInsensitiveContains(query)
        }
    }

    init(
        service: any DevRoomMemberServicing,
        initialSelectedUserIDs: Set<Int>
    ) {
        self.service = service
        draftSelectedUserIDs = initialSelectedUserIDs
    }

    func loadMembers() async {
        guard loadState != .loading else {
            return
        }

        let previousState = loadState
        loadState = .loading

        do {
            let loadedMembers = try await service.projectMembers(projectPath: GitLabWorkflowProject.path)
            guard Task.isCancelled == false else {
                loadState = previousState
                return
            }

            members = loadedMembers
            loadState = loadedMembers.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            loadState = previousState
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func toggle(_ id: Int) {
        if draftSelectedUserIDs.contains(id) {
            draftSelectedUserIDs.remove(id)
        } else {
            draftSelectedUserIDs.insert(id)
        }
    }

    func selectAll() {
        draftSelectedUserIDs.formUnion(members.map(\.id))
    }

    func clear() {
        draftSelectedUserIDs.removeAll()
    }

    func markSaved(_ ids: Set<Int>) {
        draftSelectedUserIDs = ids
    }
}
