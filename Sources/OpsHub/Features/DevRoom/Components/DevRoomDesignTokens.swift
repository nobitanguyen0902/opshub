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
}
