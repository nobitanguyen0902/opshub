import SwiftUI

struct GitLabSummaryStrip: View {
    let metrics: [GitLabSummaryMetric]
    let mode: GitLabWorkspaceLayoutMode
    let onSelect: (GitLabSummaryMetricKind) -> Void

    var body: some View {
        Group {
            if mode == .wide {
                HStack(spacing: 0) {
                    ForEach(metrics) { metric in
                        GitLabSummaryMetricView(metric: metric, onSelect: onSelect)

                        if metric.id != metrics.last?.id {
                            Divider()
                                .padding(.vertical, GitLabDesignTokens.Spacing.medium)
                        }
                    }
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 0),
                        GridItem(.flexible(), spacing: 0)
                    ],
                    spacing: 0
                ) {
                    ForEach(metrics) { metric in
                        GitLabSummaryMetricView(metric: metric, onSelect: onSelect)
                    }
                }
            }
        }
        .gitLabSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitLab summary")
    }
}

private struct GitLabSummaryMetricView: View {
    let metric: GitLabSummaryMetric
    let onSelect: (GitLabSummaryMetricKind) -> Void

    var body: some View {
        Button {
            onSelect(metric.kind)
        } label: {
            HStack(spacing: GitLabDesignTokens.Spacing.medium) {
                Image(systemName: metric.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xSmall) {
                    Text(metric.title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("\(metric.value)")
                        .font(.title2.bold())
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 0)
            }
            .padding(GitLabDesignTokens.Spacing.large)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(metric.title), \(metric.value)")
        .accessibilityHint("Opens the related GitLab section")
    }

    private var color: Color {
        switch metric.semantic {
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

#Preview("Summary — wide") {
    GitLabSummaryStrip(
        metrics: previewMetrics,
        mode: .wide,
        onSelect: { _ in }
    )
    .padding()
    .frame(width: 1_180)
}

#Preview("Summary — narrow") {
    GitLabSummaryStrip(
        metrics: previewMetrics,
        mode: .narrow,
        onSelect: { _ in }
    )
    .padding()
    .frame(width: 720)
}

private let previewMetrics = [
    GitLabSummaryMetric(kind: .awaitingReview, title: "Waiting for my review", value: 2, systemImage: "checkmark.bubble", semantic: .warning),
    GitLabSummaryMetric(kind: .mergeRequests, title: "Merge Requests", value: 4, systemImage: "arrow.triangle.branch", semantic: .information),
    GitLabSummaryMetric(kind: .assignedToMe, title: "Assigned to me", value: 12, systemImage: "person.crop.circle.badge.checkmark", semantic: .information),
    GitLabSummaryMetric(kind: .failedPipelines, title: "Failed pipelines", value: 3, systemImage: "xmark.circle", semantic: .error)
]
