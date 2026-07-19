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
    private var latestLoadRequestID = 0
    private var lastSettledLoadState: DevRoomMemberLoadState = .idle
    private var hasSuccessfulMemberCatalog = false

    var hasLoadedMembers: Bool {
        hasSuccessfulMemberCatalog
    }

    var canEditDraft: Bool {
        hasSuccessfulMemberCatalog
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
        let previousState = loadState == .loading ? lastSettledLoadState : loadState
        latestLoadRequestID += 1
        let requestID = latestLoadRequestID
        loadState = .loading

        do {
            let loadedMembers = try await service.projectMembers(projectPath: GitLabWorkflowProject.path)
            guard requestID == latestLoadRequestID else {
                return
            }
            guard Task.isCancelled == false else {
                loadState = previousState
                return
            }

            members = loadedMembers
            let settledState: DevRoomMemberLoadState = loadedMembers.isEmpty ? .empty : .loaded
            hasSuccessfulMemberCatalog = true
            loadState = settledState
            lastSettledLoadState = settledState
        } catch is CancellationError {
            guard requestID == latestLoadRequestID else {
                return
            }
            loadState = previousState
        } catch {
            guard requestID == latestLoadRequestID else {
                return
            }
            let settledState = DevRoomMemberLoadState.failed(error.localizedDescription)
            loadState = settledState
            lastSettledLoadState = settledState
        }
    }

    func toggle(_ id: Int) {
        guard canEditDraft else { return }

        if draftSelectedUserIDs.contains(id) {
            draftSelectedUserIDs.remove(id)
        } else {
            draftSelectedUserIDs.insert(id)
        }
    }

    func selectAll() {
        guard canEditDraft else { return }
        draftSelectedUserIDs.formUnion(members.map(\.id))
    }

    func clear() {
        guard canEditDraft else { return }
        draftSelectedUserIDs.removeAll()
    }

    func markSaved(_ ids: Set<Int>) {
        draftSelectedUserIDs = ids
    }
}
