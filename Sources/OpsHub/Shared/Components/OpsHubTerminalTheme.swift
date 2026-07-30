import SwiftUI

enum OpsHubTerminalTheme {
    static let controlRadius: CGFloat = 4
    static let containerRadius: CGFloat = 6
    static let borderWidth: CGFloat = 1

    static var accent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(srgbRed: 0.31, green: 0.88, blue: 0.55, alpha: 1)
            }
            return NSColor(srgbRed: 0.04, green: 0.42, blue: 0.22, alpha: 1)
        })
    }

    static var surfacePrimary: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var surfaceSecondary: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var borderSubtle: Color {
        accent.opacity(0.22)
    }

    static var borderStrong: Color {
        accent.opacity(0.58)
    }

    static var selected: Color {
        accent.opacity(0.14)
    }
}

private struct OpsHubTerminalSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isEmphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(OpsHubTerminalTheme.surfacePrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(
                        isEmphasized
                            ? OpsHubTerminalTheme.borderStrong
                            : OpsHubTerminalTheme.borderSubtle,
                        lineWidth: OpsHubTerminalTheme.borderWidth
                    )
            }
    }
}

private struct OpsHubTerminalControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(OpsHubTerminalTheme.surfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: OpsHubTerminalTheme.controlRadius)
                    .strokeBorder(OpsHubTerminalTheme.borderStrong)
            }
    }
}

private struct OpsHubTerminalControlGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: .monospaced))
            .background(OpsHubTerminalTheme.surfacePrimary)
            .clipShape(
                RoundedRectangle(cornerRadius: OpsHubTerminalTheme.controlRadius)
            )
            .overlay {
                RoundedRectangle(cornerRadius: OpsHubTerminalTheme.controlRadius)
                    .strokeBorder(OpsHubTerminalTheme.borderStrong)
            }
    }
}

private struct OpsHubTerminalInputModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal, 16)
            .frame(minHeight: 36)
            .background(OpsHubTerminalTheme.surfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: OpsHubTerminalTheme.controlRadius)
                    .strokeBorder(OpsHubTerminalTheme.borderStrong)
            }
    }
}

extension View {
    func opsHubTerminalSurface(
        cornerRadius: CGFloat = OpsHubTerminalTheme.containerRadius,
        isEmphasized: Bool = false
    ) -> some View {
        modifier(
            OpsHubTerminalSurfaceModifier(
                cornerRadius: cornerRadius,
                isEmphasized: isEmphasized
            )
        )
    }

    func opsHubTerminalControl() -> some View {
        modifier(OpsHubTerminalControlModifier())
    }

    func opsHubTerminalControlGroup() -> some View {
        modifier(OpsHubTerminalControlGroupModifier())
    }

    func opsHubTerminalInput() -> some View {
        modifier(OpsHubTerminalInputModifier())
    }
}
