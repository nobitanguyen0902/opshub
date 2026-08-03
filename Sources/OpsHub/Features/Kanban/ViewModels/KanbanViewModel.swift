import Foundation

@MainActor final class KanbanViewModel: ObservableObject {
    @Published private(set) var snapshot: KanbanBoardSnapshot?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var selectedDetail: KanbanTaskDetail?
    private let reader: any KanbanDatabaseReading
    private var refreshing = false
    init(reader: any KanbanDatabaseReading = KanbanSQLiteReader()) { self.reader = reader }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        isLoading = true
        defer { refreshing = false; isLoading = false }
        do {
            let value = try await Task.detached { try self.reader.loadBoard() }.value
            snapshot = value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func select(_ task: KanbanTask) async { do { selectedDetail = try await Task.detached { try self.reader.loadTaskDetail(taskID: task.id) }.value } catch { errorMessage = error.localizedDescription } }
}
