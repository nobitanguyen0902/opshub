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
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    SummaryCard(title: "Installed", value: "42", systemImage: "shippingbox")
        .padding()
}
