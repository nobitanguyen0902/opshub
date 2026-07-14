import SwiftUI

private struct GitLabSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    let cornerRadius: CGFloat
    let isEmphasized: Bool

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        reduceTransparency
                            ? GitLabDesignTokens.surfacePrimary
                            : GitLabDesignTokens.surfacePrimary.opacity(0.96)
                    )
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

