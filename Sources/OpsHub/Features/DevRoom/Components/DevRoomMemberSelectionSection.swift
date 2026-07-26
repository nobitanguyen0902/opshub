import SwiftUI

struct DevRoomMemberSelectionSection: View {
    @ObservedObject var viewModel: DevRoomMemberSelectionViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dev Room Members")
                        .font(.system(.callout, design: .monospaced).weight(.semibold))
                        .textCase(.uppercase)
                    Text(GitLabWorkflowProject.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(viewModel.draftSelectedUserIDs.count) selected")
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(OpsHubTerminalTheme.accent)
            }

            TextField("Search members", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .focusEffectDisabled()
                .opsHubTerminalInput()
                .disabled(viewModel.canEditDraft == false)

            HStack {
                Button("Select All") {
                    viewModel.selectAll()
                }
                .buttonStyle(.plain)
                .opsHubTerminalControl()
                .disabled(viewModel.canEditDraft == false || viewModel.members.isEmpty)

                Button("Clear") {
                    viewModel.clear()
                }
                .buttonStyle(.plain)
                .opsHubTerminalControl()
                .disabled(viewModel.canEditDraft == false || viewModel.draftSelectedUserIDs.isEmpty)
            }

            memberContent
        }
    }

    @ViewBuilder
    private var memberContent: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading project members…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        case .empty:
            ContentUnavailableView(
                "No project members",
                systemImage: "person.2.slash",
                description: Text("No members were returned for \(GitLabWorkflowProject.path).")
            )
        case let .failed(message):
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Could not load project members")
                        .font(.subheadline.weight(.medium))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("Retry") {
                    Task { await viewModel.loadMembers() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            if viewModel.filteredMembers.isEmpty {
                ContentUnavailableView(
                    "No matching members",
                    systemImage: "magnifyingglass",
                    description: Text("Try another name or username.")
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredMembers) { member in
                        DevRoomMemberSelectionRow(
                            member: member,
                            isSelected: viewModel.draftSelectedUserIDs.contains(member.id),
                            onToggle: { viewModel.toggle(member.id) }
                        )

                        if member.id != viewModel.filteredMembers.last?.id {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 8)
                .opsHubTerminalSurface(cornerRadius: OpsHubTerminalTheme.controlRadius)
            }
        }
    }
}

private struct DevRoomMemberSelectionRow: View {
    let member: DevRoomProjectMember
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(
                        isSelected
                            ? OpsHubTerminalTheme.accent
                            : Color.primary.opacity(0.55)
                    )
                    .font(.title3)

                AsyncImage(url: member.avatarURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Image(systemName: "person.crop.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 30, height: 30)
                .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(.subheadline, design: .monospaced).weight(.medium))
                    Text("@\(member.username) · ID \(member.id) · \(member.accessLevelTitle)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(member.name), @\(member.username)")
        .accessibilityValue(isSelected ? "Đã chọn" : "Chưa chọn")
    }
}
