import XCTest
@testable import OpsHub

final class AppSectionTests: XCTestCase {
    func testDevRoomAppearsAfterDashboardWithoutRemovingExistingSections() {
        XCTAssertEqual(
            AppSection.allCases,
            [.dashboard, .devRoom, .brew, .gitLab, .settings]
        )
        XCTAssertEqual(AppSection.devRoom.title, "Dev Room")
        XCTAssertEqual(AppSection.devRoom.systemImage, "person.3.fill")
    }
}
