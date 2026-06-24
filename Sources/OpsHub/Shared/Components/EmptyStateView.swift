import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    init(systemImage: String, title: String, message: String) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
    }

    var body: some View {
        ContentUnavailableView(
            title,
            systemImage: systemImage,
            description: Text(message)
        )
    }
}

#Preview {
    EmptyStateView(
        systemImage: "tray",
        title: "Nothing here yet",
        message: "Run a command to see its output."
    )
}
