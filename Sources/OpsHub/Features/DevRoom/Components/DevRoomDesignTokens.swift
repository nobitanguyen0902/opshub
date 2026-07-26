import SwiftUI

enum DevRoomDesignTokens {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let cornerRadius = OpsHubTerminalTheme.containerRadius
    static var terminalAccent: Color { OpsHubTerminalTheme.accent }
    static var surfacePrimary: Color { OpsHubTerminalTheme.surfacePrimary }
    static var borderSubtle: Color { OpsHubTerminalTheme.borderSubtle }
    static var borderStrong: Color { OpsHubTerminalTheme.borderStrong }
    static let officeWallColor = Color(red: 0.95, green: 0.93, blue: 0.88)
    static let officeFloorColor = Color(red: 0.84, green: 0.76, blue: 0.66)
    static let officeFurnitureColor = Color(red: 0.38, green: 0.25, blue: 0.16)
    static let officeLaptopColor = Color(red: 0.20, green: 0.27, blue: 0.35)
    static let officePlantColor = Color(red: 0.20, green: 0.48, blue: 0.31)
    static let drawerWidth: CGFloat = 360

    static func color(for stage: DevRoomWorkflowStage) -> Color {
        switch stage {
        case .todo: .gray
        case .doing: .blue
        case .toTest: .orange
        case .testing: .purple
        case .passed: .green
        }
    }

    static func skinColor(_ tone: DevRoomChibiSkinTone) -> Color {
        switch tone {
        case .light:
            Color(red: 1.00, green: 0.86, blue: 0.77)
        case .warm:
            Color(red: 0.93, green: 0.73, blue: 0.60)
        case .tan:
            Color(red: 0.77, green: 0.55, blue: 0.40)
        case .deep:
            Color(red: 0.55, green: 0.36, blue: 0.27)
        }
    }

    static func hairColor(_ color: DevRoomChibiHairColor) -> Color {
        switch color {
        case .charcoal:
            Color(red: 0.18, green: 0.20, blue: 0.24)
        case .black:
            Color(red: 0.07, green: 0.08, blue: 0.10)
        case .brown:
            Color(red: 0.29, green: 0.18, blue: 0.12)
        case .auburn:
            Color(red: 0.51, green: 0.24, blue: 0.15)
        }
    }

    static func shirtColor(_ color: DevRoomChibiShirtColor) -> Color {
        switch color {
        case .blue:
            Color(red: 0.27, green: 0.49, blue: 0.84)
        case .green:
            Color(red: 0.24, green: 0.63, blue: 0.44)
        case .orange:
            Color(red: 0.91, green: 0.49, blue: 0.22)
        case .purple:
            Color(red: 0.55, green: 0.38, blue: 0.79)
        case .rose:
            Color(red: 0.86, green: 0.36, blue: 0.54)
        case .teal:
            Color(red: 0.18, green: 0.62, blue: 0.64)
        }
    }
}

struct DevRoomWorkstationTransitionPolicy: Equatable {
    enum Kind: Equatable {
        case fade
        case fadeAndScale
    }

    let kind: Kind
    let duration: TimeInterval
    let scale: CGFloat

    var movesWorkstations: Bool { false }

    static func policy(reduceMotion: Bool) -> Self {
        if reduceMotion {
            return Self(kind: .fade, duration: 0.12, scale: 1)
        }
        return Self(kind: .fadeAndScale, duration: 0.18, scale: 0.97)
    }

    var transition: AnyTransition {
        switch kind {
        case .fade:
            return .opacity
        case .fadeAndScale:
            return .opacity.combined(with: .scale(scale: scale))
        }
    }

    var animation: Animation {
        .easeOut(duration: duration)
    }

    var animatedTransition: AnyTransition {
        transition.animation(animation)
    }
}

struct DevRoomDrawerTransitionPolicy: Equatable {
    enum Kind: Equatable {
        case fade
        case slideAndFade
    }

    let kind: Kind
    let duration: TimeInterval

    var animatesRoomSurface: Bool { false }

    static func policy(reduceMotion: Bool) -> Self {
        reduceMotion
            ? Self(kind: .fade, duration: 0.12)
            : Self(kind: .slideAndFade, duration: 0.24)
    }

    private var transition: AnyTransition {
        switch kind {
        case .fade:
            return .opacity
        case .slideAndFade:
            return .move(edge: .trailing).combined(with: .opacity)
        }
    }

    var animatedTransition: AnyTransition {
        transition.animation(.easeOut(duration: duration))
    }
}

struct DevRoomOfficeLayout: Equatable {
    static let minimumWorkstationWidth: CGFloat = 220
    static let horizontalPadding: CGFloat = 24
    static let columnSpacing: CGFloat = 24
    static let rowSpacing: CGFloat = 34
    static let workstationTopPadding: CGFloat = 112
    static let workstationBottomPadding: CGFloat = 36
    static let workstationHeight: CGFloat = 238
    static let minimumSceneHeight: CGFloat = 560
    static let pageHorizontalPadding = DevRoomDesignTokens.pagePadding
    static let minimumOfficeWidth = minimumWorkstationWidth + (horizontalPadding * 2)
    static let minimumRootWidth = minimumOfficeWidth + (pageHorizontalPadding * 2)

    let availableWidth: CGFloat
    let employeeCount: Int

    init(availableWidth: CGFloat, employeeCount: Int) {
        self.availableWidth = max(0, availableWidth)
        self.employeeCount = max(0, employeeCount)
    }

    var columnCount: Int {
        let contentWidth = gridWidth
        return max(
            1,
            Int((contentWidth + Self.columnSpacing) / (Self.minimumWorkstationWidth + Self.columnSpacing))
        )
    }

    var effectiveAvailableWidth: CGFloat {
        max(availableWidth, Self.minimumOfficeWidth)
    }

    static func effectiveRootWidth(for availableWidth: CGFloat) -> CGFloat {
        max(0, max(availableWidth, minimumRootWidth))
    }

    static func officeWidth(forRootWidth rootWidth: CGFloat) -> CGFloat {
        max(0, effectiveRootWidth(for: rootWidth) - (pageHorizontalPadding * 2))
    }

    var gridWidth: CGFloat {
        effectiveAvailableWidth - (Self.horizontalPadding * 2)
    }

    var workstationWidth: CGFloat {
        let gapsWidth = CGFloat(max(0, columnCount - 1)) * Self.columnSpacing
        return (gridWidth - gapsWidth) / CGFloat(columnCount)
    }

    var hasHorizontalOverflow: Bool {
        workstationWidth < Self.minimumWorkstationWidth
    }

    var workstationsDoNotOverlap: Bool {
        workstationWidth >= Self.minimumWorkstationWidth
    }

    var rowCount: Int {
        max(1, (employeeCount + columnCount - 1) / columnCount)
    }

    var sceneHeight: CGFloat {
        let workstationRowsHeight = CGFloat(rowCount) * Self.workstationHeight
        let rowGapsHeight = CGFloat(max(0, rowCount - 1)) * Self.rowSpacing
        return max(
            Self.minimumSceneHeight,
            Self.workstationTopPadding + workstationRowsHeight + rowGapsHeight + Self.workstationBottomPadding
        )
    }
}
