import SwiftUI

private struct GitLabSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let isEmphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(GitLabDesignTokens.surfacePrimary)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isEmphasized
                            ? GitLabDesignTokens.borderStrong
                            : GitLabDesignTokens.borderSubtle,
                        lineWidth: GitLabDesignTokens.borderWidth
                    )
            }
    }
}

extension View {
    func gitLabSurface(
        cornerRadius: CGFloat = GitLabDesignTokens.Radius.container,
        isEmphasized: Bool = false
    ) -> some View {
        modifier(
            GitLabSurfaceModifier(
                cornerRadius: cornerRadius,
                isEmphasized: isEmphasized
            )
        )
    }
}

private struct GitLabTerminalControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(.callout, design: .monospaced))
            .padding(.horizontal, GitLabDesignTokens.Spacing.medium)
            .frame(minHeight: 34)
            .background(GitLabDesignTokens.surfacePrimary)
            .overlay {
                RoundedRectangle(cornerRadius: GitLabDesignTokens.Radius.control)
                    .strokeBorder(GitLabDesignTokens.borderStrong)
            }
    }
}

extension View {
    func gitLabTerminalControl() -> some View {
        modifier(GitLabTerminalControlModifier())
    }
}
