import SwiftUI

struct DevRoomOfficeBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let wallHeight = proxy.size.height * 0.28
            let showsTwoWindows = proxy.size.width >= 760

            ZStack(alignment: .top) {
                DevRoomDesignTokens.officeWallColor
                    .frame(height: wallHeight)
                    .frame(maxWidth: .infinity, alignment: .top)

                DevRoomDesignTokens.officeFloorColor
                    .frame(
                        width: proxy.size.width,
                        height: max(0, proxy.size.height - wallHeight),
                        alignment: .top
                    )
                    .offset(y: wallHeight)

                floorTexture(wallHeight: wallHeight)

                HStack(spacing: showsTwoWindows ? 110 : 0) {
                    officeWindow
                    if showsTwoWindows {
                        officeWindow
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 24)

                officeClock
                    .position(x: proxy.size.width / 2, y: max(30, wallHeight * 0.54))

                HStack {
                    plant
                    Spacer()
                    if showsTwoWindows {
                        plant
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, max(wallHeight - 62, 16))
            }
        }
        .accessibilityHidden(true)
    }

    private func floorTexture(wallHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: wallHeight)

            GeometryReader { proxy in
                VStack(spacing: 0) {
                    ForEach(0 ..< 12, id: \.self) { index in
                        Rectangle()
                            .fill(Color.black.opacity(0.05))
                            .frame(height: 1)
                            .offset(y: CGFloat(index) * 30)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .allowsHitTesting(false)
    }

    private var officeWindow: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(red: 0.72, green: 0.86, blue: 0.94))
            .frame(width: 116, height: 58)
            .overlay {
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2)
                Rectangle()
                    .fill(Color.white.opacity(0.7))
                    .frame(height: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.8), lineWidth: 4)
            }
    }

    private var officeClock: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.92))
                .frame(width: 34, height: 34)
            Circle()
                .stroke(Color.black.opacity(0.18), lineWidth: 1)
                .frame(width: 34, height: 34)
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 2, height: 10)
                .offset(y: -4)
            Capsule()
                .fill(Color.black.opacity(0.55))
                .frame(width: 8, height: 2)
                .offset(x: 3)
        }
    }

    private var plant: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: -7) {
                Capsule()
                    .fill(DevRoomDesignTokens.officePlantColor)
                    .rotationEffect(.degrees(-35))
                Capsule()
                    .fill(DevRoomDesignTokens.officePlantColor)
                    .rotationEffect(.degrees(25))
                Capsule()
                    .fill(DevRoomDesignTokens.officePlantColor)
                    .rotationEffect(.degrees(48))
            }
            .frame(width: 20, height: 36)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color(red: 0.77, green: 0.46, blue: 0.28))
                .frame(width: 25, height: 16)
        }
        .frame(width: 40, height: 50, alignment: .bottom)
    }
}
