import SwiftUI

struct OpsHubFeatureHeader<Controls: View, Status: View>: View {
    let eyebrow: String
    let title: String
    let metadata: String

    private let controls: Controls
    private let status: Status

    init(
        eyebrow: String,
        title: String,
        metadata: String,
        @ViewBuilder controls: () -> Controls,
        @ViewBuilder status: () -> Status
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.metadata = metadata
        self.controls = controls()
        self.status = status()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    titleBlock

                    Spacer(minLength: 12)

                    controls
                        .fixedSize(horizontal: true, vertical: false)
                }

                VStack(alignment: .leading, spacing: 14) {
                    titleBlock

                    controls
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            status
        }
        .padding(16)
        .opsHubTerminalSurface(isEmphasized: true)
        .accessibilityElement(children: .contain)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(">")
                    .foregroundStyle(OpsHubTerminalTheme.accent)

                Text(eyebrow)
            }
            .font(.system(.caption, design: .monospaced).weight(.semibold))

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .monospaced))

            Text(metadata)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

extension OpsHubFeatureHeader where Status == EmptyView {
    init(
        eyebrow: String,
        title: String,
        metadata: String,
        @ViewBuilder controls: () -> Controls
    ) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            metadata: metadata,
            controls: controls,
            status: { EmptyView() }
        )
    }
}

extension OpsHubFeatureHeader where Controls == EmptyView, Status == EmptyView {
    init(eyebrow: String, title: String, metadata: String) {
        self.init(
            eyebrow: eyebrow,
            title: title,
            metadata: metadata,
            controls: { EmptyView() },
            status: { EmptyView() }
        )
    }
}

#Preview("Feature header — controls") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / DASHBOARD",
        title: "Sprint health",
        metadata: "milestone=Sprint 32 · updated=10:30"
    ) {
        Button("Refresh", systemImage: "arrow.clockwise") {}
            .buttonStyle(.plain)
            .opsHubTerminalControl()
    }
    .padding()
    .frame(width: 900)
}

#Preview("Feature header — narrow") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / BREW",
        title: "Package manager",
        metadata: "source=homebrew · mode=local"
    ) {
        HStack {
            Button("Refresh") {}
            Button("Check Outdated") {}
            Button("Update All") {}
        }
        .buttonStyle(.plain)
    }
    .padding()
    .frame(width: 520)
}

#Preview("Feature header — no controls") {
    OpsHubFeatureHeader(
        eyebrow: "OPSHUB / SETTINGS",
        title: "Preferences",
        metadata: "Configure OpsHub and local integrations."
    )
    .padding()
    .frame(width: 700)
}
