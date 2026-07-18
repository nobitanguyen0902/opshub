import SwiftUI

struct DevRoomWorkflowSummary: View {
    let data: DevRoomData
    let selectedStage: DevRoomWorkflowStage?
    let onSelect: (DevRoomWorkflowStage) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5),
            spacing: 12
        ) {
            ForEach(DevRoomWorkflowStage.allCases) { stage in
                Button {
                    onSelect(stage)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(stage.title, systemImage: "circle.fill")
                            .foregroundStyle(DevRoomDesignTokens.color(for: stage))
                        Text("\(data.count(for: stage))")
                            .font(.title.bold())
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(
                                reduceMotion ? nil : .smooth(duration: 0.24),
                                value: data.count(for: stage)
                            )
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                    .padding()
                    .background(
                        selectedStage == stage
                            ? DevRoomDesignTokens.color(for: stage).opacity(0.12)
                            : Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: DevRoomDesignTokens.cornerRadius)
                            .stroke(
                                selectedStage == stage
                                    ? DevRoomDesignTokens.color(for: stage)
                                    : Color(nsColor: .separatorColor)
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
