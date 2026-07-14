import SwiftUI

enum GitLabWorkspaceLayoutMode: Hashable, Sendable {
    case narrow
    case compact
    case wide

    init(width: CGFloat) {
        if width >= 1_180 {
            self = .wide
        } else if width >= 840 {
            self = .compact
        } else {
            self = .narrow
        }
    }

    var pagePadding: CGFloat {
        switch self {
        case .wide:
            32
        case .compact:
            24
        case .narrow:
            16
        }
    }
}

struct GitLabAdaptiveLayout<Content: View>: View {
    let content: (GitLabWorkspaceLayoutMode) -> Content

    init(@ViewBuilder content: @escaping (GitLabWorkspaceLayoutMode) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { proxy in
            let mode = GitLabWorkspaceLayoutMode(width: proxy.size.width)
            content(mode)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

#Preview("Adaptive widths") {
    GitLabAdaptiveLayout { mode in
        Text(String(describing: mode))
            .padding(mode.pagePadding)
    }
    .frame(width: 960, height: 300)
}

