import SwiftUI

struct DevRoomEmployeeDesk: View {
    let summary: DevRoomEmployeeSummary
    let selectedStage: DevRoomWorkflowStage?
    let animationEvent: DevRoomAnimationEvent?
    let isWindowActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    @State private var pulse = false
    @State private var pulseTask: Task<Void, Never>?

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                employeeCard
                DevRoomCharacterView(
                    employeeID: summary.employee.id,
                    isActive: isWindowActive,
                    reduceMotion: reduceMotion
                )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.025 : 1)
        .accessibilityLabel("\(summary.employee.name), \(summary.total) task")
        .onChange(of: animationEvent?.generation) {
            guard isWindowActive,
                  reduceMotion == false,
                  animationEvent?.employeeIDs.contains(summary.employee.id) == true else {
                return
            }

            pulseTask?.cancel()
            withAnimation(.spring(duration: 0.28)) {
                pulse = true
            }
            pulseTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(320))
                } catch {
                    return
                }

                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    pulse = false
                }
            }
        }
        .onChange(of: isWindowActive) {
            guard isWindowActive == false else { return }
            cancelPulse()
        }
        .onChange(of: reduceMotion) {
            guard reduceMotion else { return }
            cancelPulse()
        }
        .onDisappear {
            cancelPulse()
        }
    }

    private var employeeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.employee.name)
                        .font(.headline)
                    Text("\(summary.total) task")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            ForEach(summary.previewIssues(for: selectedStage)) { issue in
                Text("• #\(issue.iid) \(issue.title)")
                    .font(.caption)
                    .lineLimit(1)
            }

            HStack(spacing: 0) {
                ForEach(DevRoomWorkflowStage.allCases) { stage in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(DevRoomDesignTokens.color(for: stage))
                            .frame(width: 7, height: 7)
                        Text("\(summary.count(for: stage))")
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(
                                reduceMotion ? nil : .smooth(duration: 0.24),
                                value: summary.count(for: stage)
                            )
                    }
                    .font(.caption2)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 128, alignment: .topLeading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
        )
        .overlay {
            RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                .stroke(Color(nsColor: .separatorColor))
        }
    }

    private func cancelPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        pulse = false
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = summary.employee.avatarURL {
            AsyncImage(url: avatarURL) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 38, height: 38)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .foregroundStyle(.secondary)
                .frame(width: 38, height: 38)
        }
    }
}
