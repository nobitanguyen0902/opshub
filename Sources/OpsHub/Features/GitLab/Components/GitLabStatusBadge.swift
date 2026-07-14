import SwiftUI

enum GitLabStatusSeverity: Hashable, Sendable {
    case information
    case success
    case warning
    case error
    case neutral

    var color: Color {
        switch self {
        case .information:
            .blue
        case .success:
            .green
        case .warning:
            .orange
        case .error:
            .red
        case .neutral:
            .secondary
        }
    }
}

struct GitLabStatusBadge: View {
    let title: String
    let systemImage: String?
    let severity: GitLabStatusSeverity

    init(
        title: String,
        systemImage: String? = nil,
        severity: GitLabStatusSeverity
    ) {
        self.title = title
        self.systemImage = systemImage
        self.severity = severity
    }

    var body: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }

            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(severity.color)
        .padding(.horizontal, GitLabDesignTokens.Spacing.small)
        .padding(.vertical, GitLabDesignTokens.Spacing.xSmall)
        .background(severity.color.opacity(0.14), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

#Preview("Status badges") {
    HStack {
        GitLabStatusBadge(title: "Open", systemImage: "circle", severity: .success)
        GitLabStatusBadge(title: "Reviewing", systemImage: "clock", severity: .warning)
        GitLabStatusBadge(title: "Failed", systemImage: "xmark.circle", severity: .error)
    }
    .padding()
}
