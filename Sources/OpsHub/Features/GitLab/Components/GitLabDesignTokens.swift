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
        static let control: CGFloat = 8
        static let row: CGFloat = 10
        static let container: CGFloat = 12
    }

    static let borderWidth: CGFloat = 1

    static var surfacePrimary: Color {
        Color(nsColor: .controlBackgroundColor)
    }

    static var surfaceSecondary: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var surfaceHover: Color {
        Color.primary.opacity(0.06)
    }

    static var surfaceSelected: Color {
        Color.accentColor.opacity(0.14)
    }

    static var borderSubtle: Color {
        Color.primary.opacity(0.10)
    }

    static var borderStrong: Color {
        Color.primary.opacity(0.22)
    }
}

