import SwiftUI

struct DevRoomWorkflowSummary: View {
    let data: DevRoomData
    let selectedStage: DevRoomWorkflowStage?
    let onSelect: (DevRoomWorkflowStage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5),
            spacing: 8
        ) {
            ForEach(DevRoomWorkflowStage.allCases) { stage in
                Button {
                    onSelect(stage)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(stage.title, systemImage: "circle.fill")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .textCase(.uppercase)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(DevRoomDesignTokens.color(for: stage))
                        Text("\(data.count(for: stage))")
                            .font(.system(.title2, design: .monospaced).bold())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(
                                reduceMotion ? nil : .smooth(duration: 0.24),
                                value: data.count(for: stage)
                            )
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        selectedStage == stage
                            ? DevRoomDesignTokens.color(for: stage).opacity(0.12)
                            : DevRoomDesignTokens.surfacePrimary,
                        in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                            .stroke(
                                selectedStage == stage
                                    ? DevRoomDesignTokens.color(for: stage)
                                    : DevRoomDesignTokens.borderSubtle
                            )
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(stage.title), \(data.count(for: stage)) task")
                .accessibilityAddTraits(selectedStage == stage ? .isSelected : [])
            }
        }
    }
}
