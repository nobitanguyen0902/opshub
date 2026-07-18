import SwiftUI

struct DevRoomView: View {
    @ObservedObject var viewModel: DevRoomViewModel

    var body: some View {
        Text("Dev Room")
            .navigationTitle("Dev Room")
    }
}
