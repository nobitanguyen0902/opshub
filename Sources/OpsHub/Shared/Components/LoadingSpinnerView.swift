import SwiftUI

struct LoadingSpinnerView: View {
    var body: some View {
        ProgressView()
            .progressViewStyle(.circular)
            .controlSize(.small)
            .frame(width: 18, height: 18)
            .fixedSize()
    }
}
