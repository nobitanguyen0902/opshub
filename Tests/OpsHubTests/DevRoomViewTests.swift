import XCTest
@testable import OpsHub

final class DevRoomViewTests: XCTestCase {
    @MainActor
    func testWorkflowSummaryDataExcludesHiddenAssignees() async {
        let service = DevRoomViewStubService(issues: [
            source(id: 1, employeeID: 10, labels: ["Todo"]),
            source(id: 2, employeeID: 20, labels: ["Passed"])
        ])
        let viewModel = DevRoomViewModel(service: service, selectedUserIDs: [20])

        await viewModel.refresh()

        let view = DevRoomView(viewModel: viewModel)
        XCTAssertEqual(view.workflowSummaryData.count(for: .todo), 0)
        XCTAssertEqual(view.workflowSummaryData.count(for: .passed), 1)
    }

    @MainActor
    func testWorkstationPreservesUsernameForCharacterProfileLookup() {
        let expectedProfile = DevRoomChibiProfile(
            skinTone: .warm,
            hairStyle: .sidePart,
            hairColor: .brown,
            shirtColor: .teal,
            accessory: .glasses
        )
        let employee = DevRoomEmployee(
            id: 41,
            name: "Alice",
            username: "alice.dev",
            avatarURL: nil
        )
        let workstation = DevRoomWorkstation(
            summary: DevRoomEmployeeSummary(employee: employee, issues: []),
            animationEvent: nil,
            isWindowActive: false,
            reduceMotion: true,
            onSelect: {}
        )
        let character = DevRoomCharacterView(
            employee: workstation.characterEmployee,
            isActive: false,
            reduceMotion: true,
            profileStore: DevRoomChibiProfileStore(
                curatedByUsername: ["alice.dev": expectedProfile]
            )
        )

        XCTAssertEqual(workstation.characterEmployee.username, "alice.dev")
        XCTAssertEqual(character.profile, expectedProfile)
    }

    func testDetailDrawerCapsWidthAndKeepsBothInsetsWhenNarrow() {
        let widePlacement = DevRoomDetailDrawerLayout.placement(for: 1_000)
        XCTAssertEqual(widePlacement.width, 360)
        XCTAssertEqual(widePlacement.trailingInset, 0)
        XCTAssertEqual(widePlacement.leadingInset, 640)

        let narrowPlacement = DevRoomDetailDrawerLayout.placement(for: 300)
        XCTAssertEqual(narrowPlacement.width, 268)
        XCTAssertEqual(narrowPlacement.leadingInset, 16)
        XCTAssertEqual(narrowPlacement.trailingInset, 16)

        let constrainedPlacement = DevRoomDetailDrawerLayout.placement(for: 20)
        XCTAssertEqual(constrainedPlacement.width, 0)
        XCTAssertEqual(constrainedPlacement.leadingInset, 10)
        XCTAssertEqual(constrainedPlacement.trailingInset, 10)
    }

    func testOfficeLayoutUsesStableColumnBreakpointsAndSpacing() {
        let narrow = DevRoomOfficeLayout(availableWidth: 511, employeeCount: 3)
        let twoColumns = DevRoomOfficeLayout(availableWidth: 512, employeeCount: 3)
        let threeColumns = DevRoomOfficeLayout(availableWidth: 756, employeeCount: 7)

        XCTAssertEqual(narrow.columnCount, 1)
        XCTAssertEqual(twoColumns.columnCount, 2)
        XCTAssertEqual(threeColumns.columnCount, 3)
        XCTAssertEqual(threeColumns.rowCount, 3)
        XCTAssertEqual(DevRoomOfficeLayout.horizontalPadding, 24)
        XCTAssertEqual(DevRoomOfficeLayout.columnSpacing, 24)
        XCTAssertEqual(DevRoomOfficeLayout.rowSpacing, 34)
    }

    func testOfficeLayoutKeepsSceneTallEnoughForWorkstationRows() {
        let compact = DevRoomOfficeLayout(availableWidth: 512, employeeCount: 2)
        let expanded = DevRoomOfficeLayout(availableWidth: 512, employeeCount: 3)

        XCTAssertEqual(compact.sceneHeight, DevRoomOfficeLayout.minimumSceneHeight)
        XCTAssertEqual(
            expanded.sceneHeight,
            DevRoomOfficeLayout.workstationTopPadding
                + (DevRoomOfficeLayout.workstationHeight * 2)
                + DevRoomOfficeLayout.rowSpacing
                + DevRoomOfficeLayout.workstationBottomPadding
        )
    }

    func testOfficeLayoutPreventsOverflowAndDeskOverlapAtOrBelowSafeRootWidth() {
        XCTAssertEqual(DevRoomOfficeLayout.minimumOfficeWidth, 268)
        XCTAssertEqual(DevRoomOfficeLayout.minimumRootWidth, 316)

        for rootWidth in [0, 120, 315, 316] {
            let effectiveRootWidth = DevRoomOfficeLayout.effectiveRootWidth(for: CGFloat(rootWidth))
            let officeWidth = DevRoomOfficeLayout.officeWidth(forRootWidth: CGFloat(rootWidth))
            let layout = DevRoomOfficeLayout(availableWidth: officeWidth, employeeCount: 2)

            XCTAssertEqual(effectiveRootWidth, DevRoomOfficeLayout.minimumRootWidth)
            XCTAssertEqual(officeWidth, DevRoomOfficeLayout.minimumOfficeWidth)
            XCTAssertEqual(layout.effectiveAvailableWidth, DevRoomOfficeLayout.minimumOfficeWidth)
            XCTAssertEqual(layout.gridWidth, DevRoomOfficeLayout.minimumWorkstationWidth)
            XCTAssertEqual(layout.workstationWidth, DevRoomOfficeLayout.minimumWorkstationWidth)
            XCTAssertFalse(layout.hasHorizontalOverflow)
            XCTAssertTrue(layout.workstationsDoNotOverlap)
        }
    }

    @MainActor
    func testDetailDrawerPrioritizesSelectedStageAndOmitsEmptyGroups() {
        let employee = DevRoomEmployee(id: 41, name: "Alice", username: "alice.dev", avatarURL: nil)
        let summary = DevRoomEmployeeSummary(employee: employee, issues: [
            DevRoomIssue(
                id: 1,
                iid: 11,
                title: "Doing issue",
                stage: .doing,
                assignee: employee,
                updatedAt: nil,
                webURL: nil
            ),
            DevRoomIssue(
                id: 2,
                iid: 12,
                title: "Test issue",
                stage: .testing,
                assignee: employee,
                updatedAt: nil,
                webURL: URL(string: "https://gitlab.example/issues/12")
            )
        ])
        let drawer = DevRoomEmployeeDetailDrawer(
            summary: summary,
            preferredStage: .testing,
            onClose: {}
        )

        XCTAssertEqual(drawer.orderedStages.first, .testing)
        XCTAssertEqual(drawer.stagesWithIssues, [.testing, .doing])
    }

    @MainActor
    func testDrawerCloseInvokesSelectionClearAction() {
        let employee = DevRoomEmployee(id: 41, name: "Alice", username: nil, avatarURL: nil)
        var closeCount = 0
        let drawer = DevRoomEmployeeDetailDrawer(
            summary: DevRoomEmployeeSummary(employee: employee, issues: []),
            preferredStage: nil,
            onClose: { closeCount += 1 }
        )

        drawer.close()

        XCTAssertEqual(closeCount, 1)
    }

    func testDrawerFocusRouterReturnsToPreviouslySelectedVisibleWorkstation() {
        XCTAssertEqual(
            DevRoomDrawerFocusRouter.target(
                previousEmployeeID: 41,
                selectedEmployeeID: nil,
                displayedEmployeeIDs: [41, 52]
            ),
            .workstation(employeeID: 41)
        )
    }

    func testDrawerFocusRouterDoesNotTargetRemovedWorkstation() {
        XCTAssertNil(
            DevRoomDrawerFocusRouter.target(
                previousEmployeeID: 41,
                selectedEmployeeID: nil,
                displayedEmployeeIDs: [52]
            )
        )
    }

    func testDrawerFocusRouterLeavesDrawerOpeningFocusToDrawerHeading() {
        XCTAssertNil(
            DevRoomDrawerFocusRouter.target(
                previousEmployeeID: nil,
                selectedEmployeeID: 41,
                displayedEmployeeIDs: [41]
            )
        )
        XCTAssertNil(
            DevRoomDrawerFocusRouter.target(
                previousEmployeeID: 41,
                selectedEmployeeID: 52,
                displayedEmployeeIDs: [41, 52]
            )
        )
    }

    func testWorkstationTransitionPolicyUsesOnlySubtleNonLayoutMotion() {
        let policy = DevRoomWorkstationTransitionPolicy.policy(reduceMotion: false)

        XCTAssertEqual(policy.kind, .fadeAndScale)
        XCTAssertEqual(policy.duration, 0.18)
        XCTAssertEqual(policy.scale, 0.97)
        XCTAssertFalse(policy.movesWorkstations)
    }

    func testWorkstationTransitionPolicyHonorsReduceMotionWithFadeOnly() {
        let policy = DevRoomWorkstationTransitionPolicy.policy(reduceMotion: true)

        XCTAssertEqual(policy.kind, .fade)
        XCTAssertEqual(policy.duration, 0.12)
        XCTAssertEqual(policy.scale, 1)
        XCTAssertFalse(policy.movesWorkstations)
    }

    func testDrawerTransitionPolicyScopesMotionToOverlayOnly() {
        let policy = DevRoomDrawerTransitionPolicy.policy(reduceMotion: false)

        XCTAssertEqual(policy.kind, .slideAndFade)
        XCTAssertEqual(policy.duration, 0.24)
        XCTAssertFalse(policy.animatesRoomSurface)
    }

    func testDrawerTransitionPolicyHonorsReduceMotionWithFadeOnly() {
        let policy = DevRoomDrawerTransitionPolicy.policy(reduceMotion: true)

        XCTAssertEqual(policy.kind, .fade)
        XCTAssertEqual(policy.duration, 0.12)
        XCTAssertFalse(policy.animatesRoomSurface)
    }

    func testIssueWithoutURLIsNotOpenableAndExplainsWhy() {
        let employee = DevRoomEmployee(id: 41, name: "Alice", username: nil, avatarURL: nil)
        let unavailableIssue = DevRoomIssue(
            id: 1,
            iid: 11,
            title: "No link",
            stage: .doing,
            assignee: employee,
            updatedAt: nil,
            webURL: nil
        )
        let availableIssue = DevRoomIssue(
            id: 2,
            iid: 12,
            title: "Has link",
            stage: .doing,
            assignee: employee,
            updatedAt: nil,
            webURL: URL(string: "https://gitlab.example/issues/12")
        )

        XCTAssertFalse(DevRoomDetailDrawerIssuePresentation.canOpen(unavailableIssue))
        XCTAssertEqual(
            DevRoomDetailDrawerIssuePresentation.accessibilityHint(for: unavailableIssue),
            "Không có liên kết GitLab"
        )
        XCTAssertTrue(DevRoomDetailDrawerIssuePresentation.canOpen(availableIssue))
        XCTAssertEqual(
            DevRoomDetailDrawerIssuePresentation.accessibilityHint(for: availableIssue),
            "Mở issue trên GitLab"
        )
    }
}

private actor DevRoomViewStubService: DevRoomServicing {
    private let issues: [DevRoomSourceIssue]

    init(issues: [DevRoomSourceIssue]) {
        self.issues = issues
    }

    func openIssues(projectPath: String) async throws -> [DevRoomSourceIssue] {
        issues
    }
}

private func source(id: Int, employeeID: Int, labels: [String]) -> DevRoomSourceIssue {
    DevRoomSourceIssue(
        id: id,
        iid: id,
        title: "Issue \(id)",
        labels: labels,
        assignee: DevRoomEmployee(id: employeeID, name: "User \(employeeID)", username: nil, avatarURL: nil),
        updatedAt: nil,
        webURL: nil
    )
}
