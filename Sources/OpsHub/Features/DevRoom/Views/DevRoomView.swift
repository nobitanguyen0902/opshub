import SwiftUI

enum DevRoomAccessibilityFocusTarget: Equatable {
    case workstation(employeeID: Int)
}

enum DevRoomDrawerFocusRouter {
    static func target(
        previousEmployeeID: Int?,
        selectedEmployeeID: Int?,
        displayedEmployeeIDs: Set<Int>
    ) -> DevRoomAccessibilityFocusTarget? {
        guard selectedEmployeeID == nil,
              let previousEmployeeID,
              displayedEmployeeIDs.contains(previousEmployeeID) else {
            return nil
        }
        return .workstation(employeeID: previousEmployeeID)
    }
}

struct DevRoomView: View {
    @ObservedObject var viewModel: DevRoomViewModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var displayedAnimationEvent: DevRoomAnimationEvent?
    @State private var officeWidth: CGFloat = 0
    @AccessibilityFocusState private var focusedWorkstationID: Int?

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
        .frame(minWidth: DevRoomOfficeLayout.minimumRootWidth)
        .navigationTitle("Dev Room")
        .task { await viewModel.loadIfNeeded() }
        .task { await viewModel.autoRefresh() }
        .onChange(of: viewModel.animationEvent?.generation) {
            displayedAnimationEvent = viewModel.animationEvent
        }
        .onChange(of: viewModel.selectedEmployeeID) { previousEmployeeID, selectedEmployeeID in
            routeAccessibilityFocus(
                previousEmployeeID: previousEmployeeID,
                selectedEmployeeID: selectedEmployeeID
            )
        }
        .onDisappear {
            displayedAnimationEvent = nil
        }
    }

    private var content: some View {
        roomContent
    }

    private var roomContent: some View {
        ZStack(alignment: .trailing) {
            roomSurface

            if let employee = viewModel.selectedEmployee {
                detailOverlay(for: employee)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand { closeDetailDrawer() }
    }

    private var roomSurface: some View {
        ScrollView {
            VStack(spacing: DevRoomDesignTokens.sectionSpacing) {
                DevRoomWorkflowSummary(
                    data: workflowSummaryData,
                    selectedStage: viewModel.selectedStage,
                    onSelect: viewModel.toggleStage
                )

                officeScene
            }
            .padding(DevRoomDesignTokens.pagePadding)
        }
    }

    private var officeScene: some View {
        ZStack(alignment: .top) {
            DevRoomOfficeBackground()

            officeSceneContent
        }
        .frame(minHeight: officeLayout.sceneHeight)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { updateOfficeWidth(proxy.size.width) }
                    .onChange(of: proxy.size.width) { updateOfficeWidth(proxy.size.width) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    @ViewBuilder
    private var officeSceneContent: some View {
        switch viewModel.loadState {
        case .idle, .initialLoading:
            ProgressView("Đang tải Dev Room…")
                .frame(maxWidth: .infinity, minHeight: DevRoomOfficeLayout.minimumSceneHeight)

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
            .frame(maxWidth: .infinity, minHeight: DevRoomOfficeLayout.minimumSceneHeight)

        case .loaded, .refreshing, .stale:
            if viewModel.displayedEmployees.isEmpty {
                ContentUnavailableView(
                    emptyRoomTitle,
                    systemImage: "person.3"
                )
                .frame(maxWidth: .infinity, minHeight: DevRoomOfficeLayout.minimumSceneHeight)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: DevRoomOfficeLayout.minimumWorkstationWidth),
                            spacing: DevRoomOfficeLayout.columnSpacing
                        )
                    ],
                    spacing: DevRoomOfficeLayout.rowSpacing
                ) {
                    ForEach(viewModel.displayedEmployees) { employee in
                        DevRoomWorkstation(
                            summary: employee,
                            animationEvent: displayedAnimationEvent,
                            isWindowActive: controlActiveState == .key,
                            reduceMotion: reduceMotion,
                            onSelect: { viewModel.selectEmployee(employee.id) }
                        )
                        .id(employee.id)
                        .accessibilityFocused($focusedWorkstationID, equals: employee.id)
                        .transition(workstationTransitionPolicy.animatedTransition)
                    }
                }
                .padding(.horizontal, DevRoomOfficeLayout.horizontalPadding)
                .padding(.top, DevRoomOfficeLayout.workstationTopPadding)
                .padding(.bottom, DevRoomOfficeLayout.workstationBottomPadding)
            }
        }
    }

    private func detailOverlay(for employee: DevRoomEmployeeSummary) -> some View {
        GeometryReader { proxy in
            let placement = DevRoomDetailDrawerLayout.placement(for: proxy.size.width)
            ZStack(alignment: .trailing) {
                Color.black.opacity(0.22)
                    .contentShape(Rectangle())
                    .onTapGesture { closeDetailDrawer() }
                    .accessibilityHidden(true)

                DevRoomEmployeeDetailDrawer(
                    summary: employee,
                    preferredStage: viewModel.selectedStage,
                    onClose: closeDetailDrawer
                )
                .frame(width: min(placement.width, DevRoomDesignTokens.drawerWidth))
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 14, x: -4)
                .padding(.trailing, placement.trailingInset)
                .transition(drawerTransitionPolicy.animatedTransition)
            }
        }
    }

    var workflowSummaryData: DevRoomData {
        viewModel.visibleData
    }

    private var officeLayout: DevRoomOfficeLayout {
        DevRoomOfficeLayout(
            availableWidth: officeWidth,
            employeeCount: viewModel.displayedEmployees.count
        )
    }

    private var workstationTransitionPolicy: DevRoomWorkstationTransitionPolicy {
        .policy(reduceMotion: reduceMotion)
    }

    private var drawerTransitionPolicy: DevRoomDrawerTransitionPolicy {
        .policy(reduceMotion: reduceMotion)
    }

    private var emptyRoomTitle: String {
        guard viewModel.hasConfiguredMembers else {
            return "Chọn thành viên Dev Room trong Settings"
        }
        guard viewModel.data.total > 0, let selectedStage = viewModel.selectedStage else {
            return "Không có task đang mở trong Dev Room"
        }
        return "Không có nhân viên ở bước \(selectedStage.title)"
    }

    private func updateOfficeWidth(_ width: CGFloat) {
        guard abs(officeWidth - width) > 0.5 else { return }
        officeWidth = width
    }

    private func closeDetailDrawer() {
        viewModel.selectEmployee(nil)
    }

    private func routeAccessibilityFocus(
        previousEmployeeID: Int?,
        selectedEmployeeID: Int?
    ) {
        let target = DevRoomDrawerFocusRouter.target(
            previousEmployeeID: previousEmployeeID,
            selectedEmployeeID: selectedEmployeeID,
            displayedEmployeeIDs: Set(viewModel.displayedEmployees.map(\.id))
        )

        guard let target else { return }

        Task { @MainActor in
            await Task.yield()
            switch target {
            case let .workstation(employeeID):
                focusedWorkstationID = employeeID
            }
        }
    }
}
