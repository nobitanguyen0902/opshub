import SwiftUI

struct GitLabPipelinesView: View {
    let mode: GitLabWorkspaceLayoutMode
    let pipelines: [GitLabPipeline]
    let loadState: GitLabSectionLoadState
    let filter: GitLabWorkspaceFilter
    let warning: String?
    @ObservedObject var viewModel: GitLabDashboardViewModel
    let onStatusChange: (Set<String>) -> Void
    let onClearFilters: () -> Void
    let onRetry: () -> Void

    @State private var expandedPipelines: Set<GitLabPipelineKey> = []

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.orange)
                        .padding(GitLabDesignTokens.Spacing.medium)
                        .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control, isEmphasized: true)
                        .accessibilityLabel("Partial pipeline results. \(warning)")
                }

                statusFilter
                pipelineList
            }

            if let notice = viewModel.pipelineActionNotice {
                GitLabPipelineActionToast(notice: notice) {
                    viewModel.dismissPipelineActionNotice(notice.id)
                }
                .padding(GitLabDesignTokens.Spacing.medium)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(10)
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(5))
                    viewModel.dismissPipelineActionNotice(notice.id)
                }
            }
        }
        .task(id: pipelines.map(\.id)) {
            guard expandedPipelines.isEmpty, let pipeline = pipelines.first else { return }
            let key = pipelineKey(pipeline)
            expandedPipelines.insert(key)
            await viewModel.loadPipelineDetails(pipeline)
        }
        .animation(.smooth(duration: 0.2), value: viewModel.pipelineActionNotice)
    }

    private var statusFilter: some View {
        Menu {
            Button("All statuses") { onStatusChange([]) }
            Divider()
            ForEach(statuses, id: \.self) { status in
                Button(status.rawValue) { onStatusChange([status.rawValue]) }
            }
        } label: {
            Label(filter.statuses.first ?? "All statuses", systemImage: "line.3.horizontal.decrease.circle")
        }
        .buttonStyle(.plain)
        .gitLabTerminalControl()
    }

    private var pipelineList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                Text("::")
                    .foregroundStyle(GitLabDesignTokens.terminalAccent)
                Text("PIPELINES")
                    .foregroundStyle(.primary)
                Text("[\(pipelines.count)]")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Spacer()
                if loadState == .refreshing {
                    LoadingSpinnerView()
                        .accessibilityLabel("Refreshing pipelines")
                }
            }
            .font(.system(.callout, design: .monospaced).weight(.semibold))
            .padding(GitLabDesignTokens.Spacing.large)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(GitLabDesignTokens.borderSubtle)
                    .frame(height: GitLabDesignTokens.borderWidth)
            }

            pipelineContent
        }
        .gitLabSurface()
    }

    @ViewBuilder
    private var pipelineContent: some View {
        if loadState == .initialLoading && pipelines.isEmpty {
            ProgressView("Loading pipelines...")
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 180)
        } else if case let .failed(message) = loadState, pipelines.isEmpty {
            VStack(spacing: GitLabDesignTokens.Spacing.medium) {
                EmptyStateView(
                    systemImage: "exclamationmark.triangle",
                    title: "Unable to load Pipelines",
                    message: message
                )
                Button("Retry", action: onRetry)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else if pipelines.isEmpty {
            VStack(spacing: GitLabDesignTokens.Spacing.medium) {
                EmptyStateView(
                    systemImage: "tray",
                    title: filter.isEmpty ? "No pipelines" : "No matching items",
                    message: filter.isEmpty
                        ? "Recent project pipelines will appear here."
                        : "Change or clear the current filters."
                )
                if filter.isEmpty == false {
                    Button("Clear filters", action: onClearFilters)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 180)
        } else {
            LazyVStack(spacing: GitLabDesignTokens.Spacing.medium) {
                ForEach(pipelines) { pipeline in
                    let key = pipelineKey(pipeline)
                    GitLabPipelineCard(
                        pipeline: pipeline,
                        mode: mode,
                        isExpanded: expandedPipelines.contains(key),
                        viewModel: viewModel
                    ) {
                        viewModel.select(.pipeline(pipeline.id))
                        if expandedPipelines.contains(key) {
                            expandedPipelines.remove(key)
                        } else {
                            expandedPipelines.insert(key)
                            Task { await viewModel.loadPipelineDetails(pipeline) }
                        }
                    }
                }
            }
            .padding(GitLabDesignTokens.Spacing.medium)
        }
    }

    private var statuses: [GitLabPipelineStatus] {
        [.running, .passed, .failed, .canceled]
    }

    private func pipelineKey(_ pipeline: GitLabPipeline) -> GitLabPipelineKey {
        GitLabPipelineKey(projectID: pipeline.projectID, pipelineID: pipeline.id)
    }
}

private struct GitLabPipelineCard: View {
    @Environment(\.openURL) private var openURL

    let pipeline: GitLabPipeline
    let mode: GitLabWorkspaceLayoutMode
    let isExpanded: Bool
    @ObservedObject var viewModel: GitLabDashboardViewModel
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: GitLabDesignTokens.Spacing.medium) {
                Button(action: onToggle) {
                    headerContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(isExpanded ? "Collapses pipeline stages" : "Expands pipeline stages")

                if let webURL = pipeline.webURL {
                    Button {
                        openURL(webURL)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .help("Open pipeline in GitLab")
                    .accessibilityLabel("Open pipeline \(pipeline.id) in GitLab")
                }
            }
            .padding(.horizontal, GitLabDesignTokens.Spacing.large)
            .padding(.vertical, GitLabDesignTokens.Spacing.medium)

            if isExpanded {
                Divider()
                expandedContent
                    .padding(GitLabDesignTokens.Spacing.large)
            }
        }
        .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control)
    }

    @ViewBuilder
    private var headerContent: some View {
        if mode == .narrow {
            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.small) {
                identity
                HStack(spacing: GitLabDesignTokens.Spacing.small) {
                    if pipeline.isTag == true {
                        tagBadge
                    }
                    statusBadge
                    creatorAvatar
                    Spacer()
                    updatedTime
                    disclosureIndicator
                }
            }
        } else {
            HStack(spacing: GitLabDesignTokens.Spacing.medium) {
                identity
                Spacer(minLength: GitLabDesignTokens.Spacing.medium)
                if pipeline.isTag == true {
                    tagBadge
                }
                statusBadge
                creatorAvatar
                updatedTime
                disclosureIndicator
            }
        }
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xSmall) {
            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                Text("Pipeline #\(pipeline.id)")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(GitLabDesignTokens.terminalAccent)
                Text(pipeline.branch)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            Text(pipeline.project)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagBadge: some View {
        GitLabStatusBadge(title: "Tag", systemImage: "tag", severity: .neutral)
    }

    private var statusBadge: some View {
        GitLabStatusBadge(
            title: pipeline.status.rawValue,
            systemImage: pipelineStatusIcon,
            severity: pipelineStatusSeverity
        )
    }

    @ViewBuilder
    private var creatorAvatar: some View {
        if let name = pipeline.userName?.trimmingCharacters(in: .whitespacesAndNewlines),
           name.isEmpty == false {
            GitLabAvatarGroup(
                participants: [
                    GitLabWorkItemParticipant(name: name, avatarURL: pipeline.userAvatarURL)
                ],
                avatarSize: 24
            )
            .help("Created by \(name)")
        }
    }

    private var updatedTime: some View {
        Text(pipeline.updatedTime)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(minWidth: 76, alignment: .trailing)
            .help(pipeline.updatedAt?.formatted(date: .abbreviated, time: .standard) ?? pipeline.updatedTime)
    }

    private var disclosureIndicator: some View {
        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            if pipeline.isTag == true {
                Label("Read-only · Tag pipeline", systemImage: "lock")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Read-only tag pipeline")
            } else if pipeline.isTag == nil {
                Label("Read-only · Pipeline type unavailable", systemImage: "lock")
                    .font(.system(.caption, design: .monospaced).weight(.medium))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Read-only because pipeline type is unavailable")
            }

            switch viewModel.pipelineDetailsState(for: pipeline) {
            case .idle, .loading:
                ProgressView("Loading stages...")
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, minHeight: 88)
            case let .failed(message):
                VStack(spacing: GitLabDesignTokens.Spacing.small) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Button("Retry") {
                        Task { await viewModel.loadPipelineDetails(pipeline, force: true) }
                    }
                    .buttonStyle(.plain)
                    .gitLabTerminalControl()
                }
                .frame(maxWidth: .infinity, minHeight: 88)
            case let .loaded(details):
                if details.stages.isEmpty {
                    EmptyStateView(
                        systemImage: "rectangle.3.group",
                        title: "No stages",
                        message: "GitLab did not return jobs for this pipeline."
                    )
                    .frame(maxWidth: .infinity, minHeight: 88)
                } else {
                    stageGrid(details.stages)
                }
            }
        }
    }

    private func stageGrid(_ stages: [GitLabPipelineStage]) -> some View {
        LazyVGrid(
            columns: mode == .narrow
                ? [GridItem(.flexible(), spacing: GitLabDesignTokens.Spacing.medium)]
                : [GridItem(.adaptive(minimum: 220), spacing: GitLabDesignTokens.Spacing.medium)],
            alignment: .leading,
            spacing: GitLabDesignTokens.Spacing.medium
        ) {
            ForEach(stages) { stage in
                GitLabPipelineStageCard(
                    pipeline: pipeline,
                    stage: stage,
                    actionState: viewModel.stageActionState(for: stage, pipeline: pipeline)
                ) { action in
                    Task {
                        await viewModel.perform(action, on: stage, pipeline: pipeline)
                    }
                }
            }
        }
    }

    private var pipelineStatusIcon: String {
        switch pipeline.status {
        case .running: "clock.arrow.circlepath"
        case .passed: "checkmark.circle"
        case .failed: "xmark.circle"
        case .canceled: "slash.circle"
        }
    }

    private var pipelineStatusSeverity: GitLabStatusSeverity {
        switch pipeline.status {
        case .running: .warning
        case .passed: .success
        case .failed: .error
        case .canceled: .neutral
        }
    }

    private var accessibilityLabel: String {
        var values = [
            "Pipeline \(pipeline.id)",
            pipeline.project,
            pipeline.isTag == true ? "Tag \(pipeline.branch)" : "Branch \(pipeline.branch)",
            pipeline.status.rawValue
        ]
        if let userName = pipeline.userName {
            values.append("Created by \(userName)")
        }
        values.append(pipeline.updatedTime)
        return values.joined(separator: ", ")
    }
}

private struct GitLabPipelineStageCard: View {
    let pipeline: GitLabPipeline
    let stage: GitLabPipelineStage
    let actionState: GitLabPipelineStageActionState
    let onAction: (GitLabPipelineStageAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.medium) {
            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                Text(stage.name.uppercased())
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .lineLimit(1)
                Spacer()
                GitLabStatusBadge(
                    title: stage.status.rawValue,
                    systemImage: stageStatusIcon,
                    severity: stageStatusSeverity
                )
            }

            Text("\(stage.jobs.count) \(stage.jobs.count == 1 ? "job" : "jobs")")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: GitLabDesignTokens.Spacing.xSmall) {
                ForEach(stage.jobs.prefix(3)) { job in
                    HStack(spacing: GitLabDesignTokens.Spacing.xSmall) {
                        Image(systemName: jobStatusIcon(job.status))
                            .foregroundStyle(jobStatusColor(job.status))
                            .accessibilityHidden(true)
                        Text(job.name)
                            .lineLimit(1)
                        Spacer()
                        Text(job.status.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(.caption, design: .monospaced))
                    .help(job.failureReason ?? job.status.rawValue)
                }

                if stage.jobs.count > 3 {
                    Text("+\(stage.jobs.count - 3) more")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
            actionContent
        }
        .padding(GitLabDesignTokens.Spacing.medium)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
        .background(GitLabDesignTokens.surfaceSecondary.opacity(0.45))
        .overlay {
            RoundedRectangle(cornerRadius: GitLabDesignTokens.Radius.control)
                .strokeBorder(stageBorderColor, lineWidth: GitLabDesignTokens.borderWidth)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actionContent: some View {
        if pipeline.allowsMutationActions == false {
            EmptyView()
        } else if case let .running(action) = actionState {
            HStack(spacing: GitLabDesignTokens.Spacing.small) {
                LoadingSpinnerView()
                Text("\(action.rawValue)…")
            }
            .frame(maxWidth: .infinity)
            .gitLabTerminalControl()
            .accessibilityLabel("\(action.rawValue) in progress for \(stage.name)")
        } else if let action = stage.availableAction {
            Button {
                onAction(action)
            } label: {
                Label(actionTitle(action), systemImage: actionIcon(action))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .gitLabTerminalControl()
            .disabled(actionState.isRunning)
            .help(actionHelp(action))
            .accessibilityLabel("\(actionTitle(action)) stage \(stage.name)")
        } else {
            Label(stage.unavailableReason, systemImage: "info.circle")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .help(stage.unavailableReason)
        }

        if case let .failed(message) = actionState {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func actionTitle(_ action: GitLabPipelineStageAction) -> String {
        let count = stage.actionableJobs(for: action).count
        switch action {
        case .build:
            return count > 1 ? "Build (\(count))" : "Build"
        case .retry:
            return count > 1 ? "Retry (\(count))" : "Retry"
        case .cancel:
            return count > 1 ? "Cancel (\(count))" : "Cancel"
        }
    }

    private func actionHelp(_ action: GitLabPipelineStageAction) -> String {
        switch action {
        case .build:
            "Run manual jobs currently available in this stage."
        case .retry:
            "Retry failed or canceled jobs in this stage."
        case .cancel:
            "Cancel active jobs in this stage."
        }
    }

    private func actionIcon(_ action: GitLabPipelineStageAction) -> String {
        switch action {
        case .build: "play.fill"
        case .retry: "arrow.clockwise"
        case .cancel: "stop.fill"
        }
    }

    private var stageStatusIcon: String {
        switch stage.status {
        case .idle: "circle"
        case .running: "clock.arrow.circlepath"
        case .pending: "hourglass"
        case .manual: "play.circle"
        case .success: "checkmark.circle"
        case .failed: "xmark.circle"
        case .canceled: "slash.circle"
        }
    }

    private var stageStatusSeverity: GitLabStatusSeverity {
        switch stage.status {
        case .running, .pending, .manual: .warning
        case .success: .success
        case .failed: .error
        case .idle, .canceled: .neutral
        }
    }

    private var stageBorderColor: Color {
        switch stage.status {
        case .running, .pending, .manual: .orange.opacity(0.55)
        case .success: .green.opacity(0.45)
        case .failed: .red.opacity(0.55)
        case .idle, .canceled: GitLabDesignTokens.borderSubtle
        }
    }

    private func jobStatusIcon(_ status: GitLabJobStatus) -> String {
        switch status {
        case .success: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .running, .preparing: "clock.arrow.circlepath"
        case .manual: "play.circle"
        case .canceled, .canceling: "slash.circle"
        case .created: "circle"
        case .pending, .scheduled, .waitingForCallback, .waitingForResource: "hourglass"
        case .skipped: "forward.end"
        }
    }

    private func jobStatusColor(_ status: GitLabJobStatus) -> Color {
        switch status {
        case .success: .green
        case .failed: .red
        case .running, .preparing, .manual, .pending, .scheduled,
             .waitingForCallback, .waitingForResource: .orange
        case .canceled, .canceling, .created, .skipped: .secondary
        }
    }
}

private struct GitLabPipelineActionToast: View {
    let notice: GitLabPipelineActionNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: GitLabDesignTokens.Spacing.small) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(notice.message)
                .font(.system(.callout, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss notification")
        }
        .padding(GitLabDesignTokens.Spacing.medium)
        .frame(maxWidth: 420, alignment: .leading)
        .gitLabSurface(cornerRadius: GitLabDesignTokens.Radius.control, isEmphasized: true)
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(notice.message)
    }

    private var icon: String {
        switch notice.severity {
        case .success: "checkmark.circle.fill"
        case .error: "exclamationmark.triangle.fill"
        case .neutral: "info.circle.fill"
        }
    }

    private var color: Color {
        switch notice.severity {
        case .success: .green
        case .error: .red
        case .neutral: GitLabDesignTokens.terminalAccent
        }
    }
}
