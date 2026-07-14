import SwiftUI

enum GitLabNavigationBadgeText {
    static func value(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 99 ? "99+" : "\(count)"
    }
}

struct GitLabWorkspaceNavigation: View {
    let mode: GitLabWorkspaceLayoutMode
    @Binding var selection: GitLabWorkspaceSection
    let badgeCount: (GitLabWorkspaceSection) -> Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
                ForEach(GitLabWorkspaceSection.allCases) { section in
                    navigationButton(for: section)
                }
            }
            .padding(GitLabDesignTokens.Spacing.xSmall)
        }
        .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control)
        .accessibilityLabel("GitLab sections")
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
        badgeCount: { section in section == .notifications ? 120 : 2 }
    )
    .padding()
    .frame(width: 900)
}
