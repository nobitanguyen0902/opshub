import SwiftUI

enum DevRoomDesignTokens {
    static let pagePadding: CGFloat = 24
    static let sectionSpacing: CGFloat = 20
    static let cardSpacing: CGFloat = 12
    static let cornerRadius: CGFloat = 12

    static func color(for stage: DevRoomWorkflowStage) -> Color {
        switch stage {
        case .todo: .gray
        case .doing: .blue
        case .toTest: .orange
        case .test: .purple
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
