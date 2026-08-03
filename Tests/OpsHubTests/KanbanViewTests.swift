import SwiftUI
import XCTest
@testable import OpsHub

final class KanbanViewTests: XCTestCase {
    func testCollapsedColumnKeepsCompactWidthAndCount() {
        XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: true), 48)
        XCTAssertEqual(KanbanColumnLayout.width(isCollapsed: false), 264)
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
