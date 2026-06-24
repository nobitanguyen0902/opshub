import SwiftUI

struct SettingsView: View {
    var body: some View {
        ContentUnavailableView(
            "Settings",
            systemImage: "gearshape",
            description: Text("Settings will be available in a future update.")
        )
        .navigationTitle("Settings")
    }
}
