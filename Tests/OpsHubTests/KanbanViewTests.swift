import SwiftUI
import XCTest
@testable import OpsHub

final class KanbanViewTests: XCTestCase {
    func testDraftFormRequiresStructuredFieldsAndValidRepository() {
        var state = KanbanDraftFormState()
        XCTAssertFalse(state.canSubmit)
        state.title = "Add report API"
        state.objective = "Export the filtered report"
        state.acceptanceCriteriaText = "Returns CSV\nKeeps existing filters"
        state.workspacePath = "/repo"
        state.validatedWorkspacePath = "/repo"
        XCTAssertTrue(state.canSubmit)
    }

    func testLiveLogFollowsOnlyWhenAlreadyAtBottom() {
        XCTAssertTrue(KanbanLogFollowPolicy.shouldFollow(distanceFromBottom: 4))
        XCTAssertFalse(KanbanLogFollowPolicy.shouldFollow(distanceFromBottom: 80))
    }

    func testInspectorUsesPreferredWidthAndKeepsInsetsWhenNarrow() {
        XCTAssertEqual(KanbanInspectorLayout.placement(for: 900), .init(width: 460, trailingInset: 0))
        XCTAssertEqual(KanbanInspectorLayout.placement(for: 400), .init(width: 368, trailingInset: 16))
    }

    @MainActor
    func testInspectorBackdropAndCloseInvokeCallbacks() {
        var closeCount = 0
        let backdrop = KanbanInspectorBackdrop { closeCount += 1 }
        backdrop.dismiss()

        let inspector = KanbanTaskInspector(
            model: KanbanViewModel(),
            card: testCard,
            onClose: { closeCount += 1 }
        )
        inspector.close()

        XCTAssertEqual(closeCount, 2)
    }

    func testInspectorFocusReturnsToPreviouslySelectedVisibleCard() {
        XCTAssertEqual(
            KanbanInspectorFocusRouter.target(
                previousCardID: testCard.id,
                selectedCardID: nil,
                displayedCardIDs: [testCard.id]
            ),
            testCard.id
        )
        XCTAssertNil(
            KanbanInspectorFocusRouter.target(
                previousCardID: testCard.id,
                selectedCardID: nil,
                displayedCardIDs: []
            )
        )
    }

    func testInspectorTransitionHonorsReduceMotionAndDoesNotMoveBoard() {
        let reduced = KanbanInspectorTransitionPolicy.policy(reduceMotion: true)
        XCTAssertEqual(reduced.kind, .fade)
        XCTAssertEqual(reduced.duration, 0.12)
        XCTAssertFalse(reduced.animatesBoardSurface)

        let normal = KanbanInspectorTransitionPolicy.policy(reduceMotion: false)
        XCTAssertEqual(normal.kind, .slideAndFade)
        XCTAssertEqual(normal.duration, 0.20)
        XCTAssertFalse(normal.animatesBoardSurface)
    }

    func testNewTaskFocusReturnsToHeaderOpenerAfterCloseOrSuccess() {
        XCTAssertEqual(
            KanbanNewTaskFocusRouter.target(
                previousIsPresenting: true,
                isPresenting: false
            ),
            .newTaskButton
        )
        XCTAssertNil(
            KanbanNewTaskFocusRouter.target(
                previousIsPresenting: false,
                isPresenting: true
            )
        )
    }
    func testCollapsedColumnKeepsCompactWidthAndCount() {
        XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: true), 48)
        XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: false), 264)
    }

    func testHeaderAndCollapseControlsKeepMinimumHitTargets() {
        XCTAssertEqual(KanbanControlLayout.headerHitTarget, 42)
        XCTAssertEqual(KanbanControlLayout.collapseHitTarget, 34)
    }

    func testCardPresentationShowsWorkspaceBasename() {
        let value = KanbanCardViewData(
            id: .hermes("t_1"),
            title: "Task",
            column: .ready,
            priority: .normal,
            displayID: "t_1",
            workspacePath: "/Users/me/opshub",
            stageLabel: nil,
            elapsed: nil,
            isWorkflowOwned: false,
            availableActions: []
        )

        XCTAssertEqual(value.workspaceName, "opshub")
    }
}

private let testCard = KanbanCardViewData(
    id: .hermes("t_1"),
    title: "Task",
    column: .ready,
    priority: .normal,
    displayID: "t_1",
    workspacePath: "/repo",
    stageLabel: nil,
    elapsed: nil,
    isWorkflowOwned: false,
    availableActions: []
)
