import SwiftUI

struct DevRoomCharacterView: View {
    let employeeID: Int
    let isActive: Bool
    let reduceMotion: Bool

    @State private var isTyping = false
    @State private var isBlinking = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 110, height: 50)
                .offset(y: 34)

            Circle()
                .fill(characterColor.opacity(0.22))
                .frame(width: 54, height: 54)
                .offset(y: isTyping ? -21 : -19)
                .overlay {
                    HStack(spacing: 12) {
                        Capsule()
                            .frame(width: 4, height: isBlinking ? 1 : 5)
                        Capsule()
                            .frame(width: 4, height: isBlinking ? 1 : 5)
                    }
                    .offset(y: -20)
                }

            hair
                .offset(y: isTyping ? -43 : -41)

            Image(systemName: "laptopcomputer")
                .font(.system(size: 48))
                .foregroundStyle(isTyping ? Color.primary : Color.secondary)
                .opacity(isTyping ? 1 : 0.72)
                .offset(y: 28)

            HStack(spacing: 26) {
                Capsule()
                Capsule()
            }
            .foregroundStyle(characterColor)
            .frame(width: 72, height: 12)
            .rotationEffect(.degrees(isTyping ? 3 : -3))
            .offset(y: 23)
        }
        .frame(height: 130)
        .task(id: animationKey) {
            guard animationKey else {
                isTyping = false
                isBlinking = false
                return
            }

            do {
                try await Task.sleep(for: initialDelay)
                while Task.isCancelled == false {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        isTyping.toggle()
                    }
                    try await Task.sleep(for: typingDelay)
                    withAnimation(.linear(duration: 0.08)) {
                        isBlinking = true
                    }
                    try await Task.sleep(for: .milliseconds(120))
                    withAnimation(.linear(duration: 0.08)) {
                        isBlinking = false
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                return
            }
        }
    }

    private var animationKey: Bool {
        isActive && reduceMotion == false
    }

    private var initialDelay: Duration {
        .milliseconds(abs(employeeID % 700))
    }

    private var typingDelay: Duration {
        .milliseconds(700 + abs(employeeID % 500))
    }

    private var characterColor: Color {
        [.blue, .green, .orange, .purple][abs(employeeID % 4)]
    }

    @ViewBuilder
    private var hair: some View {
        switch abs(employeeID % 3) {
        case 0:
            Capsule()
                .fill(Color.primary.opacity(0.72))
                .frame(width: 42, height: 12)
        case 1:
            HStack(spacing: 10) {
                Circle()
                Circle()
            }
            .foregroundStyle(Color.primary.opacity(0.72))
            .frame(width: 44, height: 16)
        default:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.primary.opacity(0.72))
                .frame(width: 34, height: 14)
                .rotationEffect(.degrees(-5))
        }
    }
}
