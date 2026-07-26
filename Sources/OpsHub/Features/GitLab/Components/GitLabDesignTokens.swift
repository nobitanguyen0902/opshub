import SwiftUI

enum GitLabDesignTokens {
    enum Spacing {
        static let xSmall: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xLarge: CGFloat = 24
        static let xxLarge: CGFloat = 32
    }

    enum Radius {
        static let control = OpsHubTerminalTheme.controlRadius
        static let row: CGFloat = 2
        static let container = OpsHubTerminalTheme.containerRadius
    }

    static let borderWidth = OpsHubTerminalTheme.borderWidth

    static var terminalAccent: Color {
        OpsHubTerminalTheme.accent
    }

    static var surfacePrimary: Color {
        OpsHubTerminalTheme.surfacePrimary
    }

    static var surfaceSecondary: Color {
        OpsHubTerminalTheme.surfaceSecondary
    }

    static var surfaceHover: Color {
        terminalAccent.opacity(0.08)
    }

    static var surfaceSelected: Color {
        OpsHubTerminalTheme.selected
    }

    static var borderSubtle: Color {
        OpsHubTerminalTheme.borderSubtle
    }

    static var borderStrong: Color {
        OpsHubTerminalTheme.borderStrong
    }
}
