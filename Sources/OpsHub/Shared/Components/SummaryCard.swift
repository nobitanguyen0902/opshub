import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let systemImage: String

    init(title: String, value: String, systemImage: String) {
        self.title = title
        self.value = value
        self.systemImage = systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title.uppercased(), systemImage: systemImage)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("::")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(OpsHubTerminalTheme.accent)
            }

            Text(value)
                .font(.system(.title2, design: .monospaced).bold())
                .monospacedDigit()
                .foregroundStyle(OpsHubTerminalTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .opsHubTerminalSurface()
    }
}

#Preview {
    SummaryCard(title: "Installed", value: "42", systemImage: "shippingbox")
        .padding()
}
