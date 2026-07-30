import SwiftUI

enum SprintDashboardInspectorFocusRouter {
    static func target(
        previousSummaryID: String?,
        selectedSummaryID: String?,
        displayedSummaryIDs: Set<String>
    ) -> String? {
        guard selectedSummaryID == nil,
              let previousSummaryID,
              displayedSummaryIDs.contains(previousSummaryID) else {
            return nil
        }
        return previousSummaryID
    }
}

private struct SprintDashboardMemberRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isSelected || configuration.isPressed
                    ? OpsHubTerminalTheme.selected
                    : Color.clear
            )
    }
}

struct DashboardView: View {
    @ObservedObject private var viewModel: SprintDashboardViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedSummaryID: String?
    @AccessibilityFocusState private var focusedSummaryID: String?

    init(viewModel: SprintDashboardViewModel) {
        self.viewModel = viewModel
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            dashboardScroll

            if let selectedSummary {
                inspectorOverlay(for: selectedSummary)
            }
        }
        .animation(
            .easeOut(duration: reduceMotion ? 0.12 : 0.20),
            value: selectedSummaryID
        )
        .onExitCommand(perform: closeInspector)
        .onChange(of: displayedSummaryIDs) { _, summaryIDs in
            guard let selectedSummaryID,
                  summaryIDs.contains(selectedSummaryID) == false else {
                return
            }
            self.selectedSummaryID = nil
        }
        .onChange(of: selectedSummaryID) { previousID, currentID in
            focusedSummaryID = SprintDashboardInspectorFocusRouter.target(
                previousSummaryID: previousID,
                selectedSummaryID: currentID,
                displayedSummaryIDs: Set(displayedSummaryIDs)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(OpsHubTerminalTheme.surfaceSecondary)
        .navigationTitle("Dashboard")
        .task {
            await viewModel.loadIfNeeded()
        }
        .task {
            await viewModel.autoRefresh()
        }
    }

    private var dashboardScroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                if viewModel.milestoneState.isLoading && viewModel.milestones.isEmpty {
                    initialLoading
                } else if let milestone = viewModel.selectedMilestone {
                    dashboardContent(milestone: milestone)
                } else {
                    noCurrentSprint
                }
            }
            .padding(20)
        }
    }

    private var selectedSummary: SprintDashboardMemberSummary? {
        guard let selectedSummaryID else { return nil }
        return viewModel.data?.memberSummaries.first {
            $0.id == selectedSummaryID
        }
    }

    private var displayedSummaryIDs: [String] {
        viewModel.data?.memberSummaries.map(\.id) ?? []
    }

    private func inspectorOverlay(
        for summary: SprintDashboardMemberSummary
    ) -> some View {
        GeometryReader { proxy in
            let placement = SprintDashboardInspectorLayout.placement(
                for: proxy.size.width
            )

            SprintDashboardMemberInspector(
                summary: summary,
                onClose: closeInspector
            )
            .id(summary.id)
            .frame(width: placement.width)
            .frame(maxHeight: .infinity)
            .background(OpsHubTerminalTheme.surfacePrimary)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OpsHubTerminalTheme.accent)
                    .frame(width: 2)
            }
            .padding(.trailing, placement.trailingInset)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .trailing
            )
        }
        .transition(
            reduceMotion
                ? .opacity
                : .move(edge: .trailing).combined(with: .opacity)
        )
        .zIndex(1)
    }

    private func closeInspector() {
        selectedSummaryID = nil
    }

    private var header: some View {
        OpsHubFeatureHeader(
            eyebrow: "OPSHUB / DASHBOARD",
            title: "Sprint health",
            metadata: headerMetadata
        ) {
            HStack(spacing: 0) {
                milestonePicker

                Divider()
                    .frame(height: 22)
                    .accessibilityHidden(true)

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isLoading {
                            LoadingSpinnerView()
                                .accessibilityHidden(true)
                        }

                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .frame(width: 116)
                    .frame(minHeight: 42)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
                .accessibilityLabel(
                    viewModel.isLoading ? "Refreshing Dashboard" : "Refresh Dashboard"
                )
                .accessibilityHint("Reloads milestones and sprint metrics from GitLab")
            }
            .opsHubTerminalControlGroup()
        } status: {
            if case let .stale(message) = viewModel.milestoneState {
                statusBanner(
                    message: "Milestone list is stale. \(message)",
                    systemImage: "exclamationmark.triangle",
                    color: .orange
                )
            } else if case let .failed(message) = viewModel.milestoneState {
                statusBanner(
                    message: message,
                    systemImage: "xmark.octagon",
                    color: .red
                )
            }
        }
    }

    private var milestonePicker: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(OpsHubTerminalTheme.accent)

            Text("Milestone:")
                .foregroundStyle(.secondary)

            Picker("", selection: selectedMilestoneBinding) {
                if viewModel.milestones.isEmpty {
                    Text("No milestones")
                        .tag(nil as Int?)
                }

                ForEach(viewModel.milestones) { milestone in
                    Text(milestone.title)
                        .tag(Optional(milestone.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(width: 300, alignment: .leading)
        .frame(minHeight: 42)
        .contentShape(Rectangle())
        .disabled(viewModel.milestones.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected milestone")
        .accessibilityValue(viewModel.selectedMilestone?.title ?? "No milestone selected")
    }

    private var selectedMilestoneBinding: Binding<Int?> {
        Binding(
            get: { viewModel.selectedMilestoneID },
            set: { milestoneID in
                guard let milestoneID else { return }
                Task { await viewModel.selectMilestone(id: milestoneID) }
            }
        )
    }

    private var initialLoading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading sprint data from GitLab…")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .opsHubTerminalSurface()
    }

    private var noCurrentSprint: some View {
        VStack(spacing: 14) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 32))
                .foregroundStyle(OpsHubTerminalTheme.accent)

            Text("No active sprint milestone")
                .font(.system(.headline, design: .monospaced))

            Text(
                viewModel.milestones.isEmpty
                    ? "Create a GitLab milestone with start and due dates, then refresh."
                    : "No milestone covers today. Select another sprint from the header."
            )
            .font(.system(.callout, design: .monospaced))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .opsHubTerminalControl()
        }
        .frame(maxWidth: .infinity, minHeight: 320)
        .padding()
        .opsHubTerminalSurface()
    }

    @ViewBuilder
    private func dashboardContent(milestone: SprintMilestone) -> some View {
        metricGrid

        sectionLabel("Team delivery")
        memberProgressPanel

        sectionLabel("Production bugs created this sprint")
        productionBugPanel

        if let lastUpdated = viewModel.lastUpdated {
            Text("last_updated=\(lastUpdated.formatted(.relative(presentation: .named)))")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var metricGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(
                    .adaptive(minimum: 210, maximum: 420),
                    spacing: 12,
                    alignment: .top
                )
            ],
            alignment: .leading,
            spacing: 12
        ) {
            SprintMetricCard(
                title: "Sprint tickets",
                value: metricValue(
                    state: viewModel.deliveryState,
                    value: viewModel.data?.ticketCount
                ),
                helper: "All issues in selected milestone",
                systemImage: "rectangle.stack",
                accent: OpsHubTerminalTheme.accent,
                state: viewModel.deliveryState
            )

            SprintMetricCard(
                title: "Released",
                value: metricValue(
                    state: viewModel.deliveryState,
                    value: viewModel.data?.releasedCount
                ),
                helper: "Passed + ToProduction + Merged",
                systemImage: "checkmark.circle",
                accent: .green,
                state: viewModel.deliveryState
            )

            SprintMetricCard(
                title: "New production bugs",
                value: metricValue(
                    state: viewModel.bugState,
                    value: viewModel.data?.productionBugCount
                ),
                helper: "Created inside sprint dates · any assignee",
                systemImage: "exclamationmark.triangle",
                accent: .orange,
                state: viewModel.bugState
            )
        }
    }

    private var memberProgressPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                title: "Member progress",
                metadata: memberPanelMetadata
            )

            if viewModel.data == nil,
               viewModel.deliveryState == .idle || viewModel.deliveryState.isLoading {
                panelLoading("Loading sprint tickets…")
            } else {
                switch viewModel.deliveryState {
                case let .failed(message):
                    panelFailure(message: message)
                default:
                    if viewModel.hasConfiguredMembers == false {
                        panelEmpty(
                            systemImage: "person.crop.circle.badge.questionmark",
                            title: "No members configured",
                            message: "Choose visible Dev Room members in Settings to show this breakdown."
                        )
                    } else if viewModel.data?.memberSummaries.isEmpty != false {
                        panelEmpty(
                            systemImage: "person.3",
                            title: "No member tickets",
                            message: "This milestone has no tickets assigned to configured members."
                        )
                    } else {
                        memberTable
                    }

                    if case let .stale(message) = viewModel.deliveryState {
                        inlineWarning(message)
                    }
                }
            }
        }
        .opsHubTerminalSurface()
    }

    private var memberTable: some View {
        VStack(spacing: 0) {
            memberTableRow(
                member: AnyView(
                    Text("MEMBER")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(.secondary)
                ),
                tickets: AnyView(tableHeader("TICKETS")),
                released: AnyView(tableHeader("RELEASED")),
                progress: AnyView(tableHeader("PROGRESS"))
            )

            Divider()

            ForEach(viewModel.data?.memberSummaries ?? []) { summary in
                Button {
                    selectedSummaryID = summary.id
                } label: {
                    memberTableRow(
                        member: AnyView(memberIdentity(summary.member)),
                        tickets: AnyView(
                            Text(summary.ticketCount.formatted())
                                .font(
                                    .system(
                                        .callout,
                                        design: .monospaced
                                    ).weight(.semibold)
                                )
                                .monospacedDigit()
                        ),
                        released: AnyView(
                            Text(summary.releasedCount.formatted())
                                .font(
                                    .system(
                                        .callout,
                                        design: .monospaced
                                    ).weight(.semibold)
                                )
                                .monospacedDigit()
                                .foregroundStyle(.green)
                        ),
                        progress: AnyView(memberProgress(summary))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(
                    SprintDashboardMemberRowButtonStyle(
                        isSelected: selectedSummaryID == summary.id
                    )
                )
                .accessibilityFocused(
                    $focusedSummaryID,
                    equals: summary.id
                )
                .accessibilityLabel(
                    "\(summary.member?.name ?? "Unassigned"), "
                        + "\(summary.ticketCount) tickets, "
                        + "\(summary.releasedCount) released"
                )
                .accessibilityHint("Shows this member's sprint tasks")

                if summary.id != viewModel.data?.memberSummaries.last?.id {
                    Divider()
                }
            }
        }
    }

    private func memberTableRow(
        member: AnyView,
        tickets: AnyView,
        released: AnyView,
        progress: AnyView
    ) -> some View {
        HStack(spacing: 12) {
            member
                .frame(maxWidth: .infinity, alignment: .leading)

            tickets
                .frame(width: 76, alignment: .center)

            released
                .frame(width: 82, alignment: .center)

            progress
                .frame(width: 170, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
    }

    private func tableHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private func memberIdentity(_ member: SprintDashboardMember?) -> some View {
        HStack(spacing: 10) {
            SprintMemberAvatar(member: member)

            VStack(alignment: .leading, spacing: 2) {
                Text(member?.name ?? "Unassigned")
                    .font(.system(.callout, design: .monospaced).weight(.medium))
                    .lineLimit(1)

                Text(member?.username.map { "@\($0)" } ?? "Needs an owner")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private func memberProgress(
        _ summary: SprintDashboardMemberSummary
    ) -> some View {
        HStack(spacing: 8) {
            ProgressView(value: summary.progress)
                .progressViewStyle(.linear)
                .tint(OpsHubTerminalTheme.accent)

            Text(summary.progress.formatted(.percent.precision(.fractionLength(0))))
                .font(.system(.caption2, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Release progress")
        .accessibilityValue(
            "\(summary.releasedCount) of \(summary.ticketCount) released, "
                + "\(Int((summary.progress * 100).rounded())) percent"
        )
    }

    private var productionBugPanel: some View {
        VStack(spacing: 0) {
            panelHeader(
                title: "New production bugs",
                metadata: bugPanelMetadata
            )

            if viewModel.data == nil,
               viewModel.bugState == .idle || viewModel.bugState.isLoading {
                panelLoading("Loading production bugs…")
            } else {
                switch viewModel.bugState {
                case let .failed(message):
                    panelFailure(message: message)
                default:
                    if viewModel.data?.productionBugPreview.isEmpty != false {
                        panelEmpty(
                            systemImage: "checkmark.shield",
                            title: "No production bugs",
                            message: "No production bugs were created in this sprint."
                        )
                    } else {
                        ForEach(viewModel.data?.productionBugPreview ?? []) { issue in
                            productionBugRow(issue)
                            if issue.id != viewModel.data?.productionBugPreview.last?.id {
                                Divider()
                            }
                        }
                    }

                    if case let .stale(message) = viewModel.bugState {
                        inlineWarning(message)
                    }
                }
            }
        }
        .opsHubTerminalSurface()
    }

    private func productionBugRow(
        _ issue: SprintDashboardIssue
    ) -> some View {
        Button {
            if let webURL = issue.webURL {
                openURL(webURL)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.title)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text("\(issue.project) #\(issue.iid)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                SprintMemberAvatar(member: issue.assignee)
                    .help(issue.assignee?.name ?? "Unassigned")

                if let date = issue.createdAt {
                    Text(date.formatted(.relative(presentation: .named)))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                if issue.webURL != nil {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(OpsHubTerminalTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(issue.webURL == nil)
        .accessibilityLabel(
            "\(issue.title), \(issue.project) issue \(issue.iid), "
                + "assigned to \(issue.assignee?.name ?? "nobody")"
        )
        .accessibilityHint(
            issue.webURL == nil
                ? "GitLab link is unavailable"
                : "Opens this issue in GitLab"
        )
    }

    private func panelHeader(
        title: String,
        metadata: String
    ) -> some View {
        HStack {
            Text(title)
                .font(.system(.callout, design: .monospaced).weight(.semibold))

            Spacer()

            Text(metadata)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 46)
        .background(OpsHubTerminalTheme.selected.opacity(0.35))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func panelLoading(_ message: String) -> some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
    }

    private func panelFailure(message: String) -> some View {
        VStack(spacing: 10) {
            Label(message, systemImage: "xmark.octagon")
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)

            Button("Retry") {
                Task { await viewModel.refresh() }
            }
            .opsHubTerminalControl()
        }
        .frame(maxWidth: .infinity, minHeight: 110)
        .padding()
    }

    private func panelEmpty(
        systemImage: String,
        title: String,
        message: String
    ) -> some View {
        VStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(.callout, design: .monospaced).weight(.semibold))

            Text(message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 100)
        .padding()
    }

    private func inlineWarning(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .top) {
                Divider()
            }
    }

    private func statusBanner(
        message: String,
        systemImage: String,
        color: Color
    ) -> some View {
        Label(message, systemImage: systemImage)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    private func metricValue(
        state: SprintDashboardSectionState,
        value: Int?
    ) -> String {
        switch state {
        case .failed:
            "—"
        case .idle, .loading, .loaded, .stale:
            value?.formatted() ?? "—"
        }
    }

    private var memberPanelMetadata: String {
        guard let data = viewModel.data else { return "—" }
        let assignedMembers = data.memberSummaries.count { $0.member != nil }
        let unassignedCount = data.memberSummaries.last?.member == nil
            ? data.memberSummaries.last?.ticketCount ?? 0
            : 0
        return "\(assignedMembers) members · \(unassignedCount) unassigned"
    }

    private var bugPanelMetadata: String {
        guard let count = viewModel.data?.productionBugCount else { return "—" }
        return "\(count) total"
    }

    private var headerMetadata: String {
        guard let milestone = viewModel.selectedMilestone else {
            return "milestone=none · timezone=Asia/Ho_Chi_Minh"
        }
        return "milestone=\(milestone.title) · "
            + "\(milestone.startDate.formatted(date: .abbreviated, time: .omitted))"
            + " — "
            + "\(milestone.dueDate.formatted(date: .abbreviated, time: .omitted))"
            + " · timezone=Asia/Ho_Chi_Minh"
    }
}

private struct SprintMetricCard: View {
    let title: String
    let value: String
    let helper: String
    let systemImage: String
    let accent: Color
    let state: SprintDashboardSectionState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title.uppercased())
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                if state.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                        .foregroundStyle(accent)
                }
            }

            Text(value)
                .font(.system(size: 30, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(accent)

            Text(helper)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .padding(15)
        .opsHubTerminalSurface(
            isEmphasized: title == "New production bugs"
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value)")
    }
}

#Preview {
    DashboardView(
        viewModel: SprintDashboardViewModel(
            service: EmptySprintDashboardService()
        )
    )
}

private struct EmptySprintDashboardService: SprintDashboardServicing {
    func sprintMilestones(projectPath: String) async throws -> [SprintMilestone] {
        []
    }

    func sprintIssues(
        projectPath: String,
        milestoneTitle: String
    ) async throws -> [SprintDashboardIssue] {
        []
    }

    func productionBugs(
        projectPath: String,
        createdAfter: Date,
        createdBefore: Date
    ) async throws -> [SprintDashboardIssue] {
        []
    }
}
