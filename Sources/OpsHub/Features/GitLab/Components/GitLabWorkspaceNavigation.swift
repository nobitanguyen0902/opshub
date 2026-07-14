import SwiftUI

enum GitLabNavigationBadgeText {
    static func value(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}

struct GitLabWorkspaceNavigation: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: GitLabWorkspaceLayoutMode
    @Binding var selection: GitLabWorkspaceSection
    let badgeCount: (GitLabWorkspaceSection) -> Int

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
                    ForEach(GitLabWorkspaceSection.allCases) { section in
                        navigationButton(for: section)
                    }
                }
                .padding(GitLabDesignTokens.Spacing.xSmall)
            }
            .onChange(of: selection) { _, section in
                if reduceMotion {
                    proxy.scrollTo(section, anchor: scrollAnchor)
                } else {
                    withAnimation(.smooth(duration: 0.2)) {
                        proxy.scrollTo(section, anchor: scrollAnchor)
                    }
                }
            }
        }
        .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control)
        .accessibilityLabel("GitLab sections")
    }

    private var scrollAnchor: UnitPoint {
        mode == .narrow ? .center : .leading
    }

    private func navigationButton(for section: GitLabWorkspaceSection) -> some View {
        let isSelected = selection == section
        let badge = GitLabNavigationBadgeText.value(for: badgeCount(section))

        return Button {
            selection = section
        } label: {
            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                Text(section.title)
                    .fontWeight(isSelected ? .semibold : .regular)

                if let badge {
                    Text(badge)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tertiary, in: Capsule())
                        .accessibilityLabel("\(badgeCount(section)) items")
                }
            }
            .padding(.horizontal, GitLabDesignTokens.Spacing.medium)
            .frame(minHeight: 36)
            .background(
                isSelected ? GitLabDesignTokens.surfaceSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: GitLabDesignTokens.Radius.control, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows the \(section.title) section")
        .id(section)
    }
}

#Preview {
    GitLabWorkspaceNavigation(
        mode: .wide,
        selection: .constant(.overview),
        badgeCount: { section in section == .pipelines ? 120 : 2 }
    )
    .padding()
    .frame(width: 900)
}
