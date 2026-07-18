import SwiftUI

struct DevRoomView: View {
    @ObservedObject var viewModel: DevRoomViewModel

    var body: some View {
        VStack(spacing: 0) {
            DevRoomHeader(
                lastUpdated: viewModel.lastUpdated,
                isRefreshing: viewModel.loadState == .initialLoading
                    || viewModel.loadState == .refreshing,
                isStale: {
                    if case .stale = viewModel.loadState { return true }
                    return false
                }(),
                onRefresh: { Task { await viewModel.refresh() } }
            )
            .padding(DevRoomDesignTokens.pagePadding)

            content
        }
        .navigationTitle("Dev Room")
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadState {
        case .idle, .initialLoading:
            ProgressView("Đang tải Dev Room…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .failed(message):
            ContentUnavailableView {
                Label("Không thể tải Dev Room", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Thử lại") {
                    Task { await viewModel.retry() }
                }
            }
        default:
            roomContent
        }
    }

    private var roomContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DevRoomDesignTokens.sectionSpacing) {
                    DevRoomWorkflowSummary(
                        data: viewModel.data,
                        selectedStage: viewModel.selectedStage,
                        onSelect: viewModel.toggleStage
                    )

                    if viewModel.displayedEmployees.isEmpty {
                        ContentUnavailableView(
                            "Không có task đang mở trong Dev Room",
                            systemImage: "person.3"
                        )
                    } else {
                        LazyVGrid(
                            columns: [
                                GridItem(
                                    .adaptive(minimum: 260),
                                    spacing: DevRoomDesignTokens.sectionSpacing
                                )
                            ],
                            spacing: 24
                        ) {
                            ForEach(viewModel.displayedEmployees) { employee in
                                DevRoomEmployeeDesk(
                                    summary: employee,
                                    selectedStage: viewModel.selectedStage,
                                    onSelect: { viewModel.selectEmployee(employee.id) }
                                )
                            }
                        }
                    }
                }
                .padding(DevRoomDesignTokens.pagePadding)
            }

            if let employee = viewModel.selectedEmployee {
                Divider()
                DevRoomEmployeeDetailPanel(
                    summary: employee,
                    preferredStage: viewModel.selectedStage,
                    onClose: { viewModel.selectEmployee(nil) }
                )
                .frame(width: 340)
            }
        }
    }
}
