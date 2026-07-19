import SwiftUI

struct DevRoomCharacterView: View {
    let employee: DevRoomEmployee
    let isActive: Bool
    let reduceMotion: Bool

    @State private var isTyping = false
    @State private var isBlinking = false

    init(employee: DevRoomEmployee, isActive: Bool, reduceMotion: Bool) {
        self.employee = employee
        self.isActive = isActive
        self.reduceMotion = reduceMotion
    }

    init(employeeID: Int, isActive: Bool, reduceMotion: Bool) {
        self.init(
            employee: DevRoomEmployee(
                id: employeeID,
                name: "",
                username: nil,
                avatarURL: nil
            ),
            isActive: isActive,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        ZStack {
            torso
            head
            hair
            eyes
            mouth
            arms
            accessory
        }
        .frame(width: 126, height: 118)
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
        .milliseconds(Int(employee.id.magnitude % 700))
    }

    private var typingDelay: Duration {
        .milliseconds(700 + Int(employee.id.magnitude % 500))
    }

    private var profile: DevRoomChibiProfile {
        DevRoomChibiProfileStore.production.profile(for: employee)
    }

    private var torso: some View {
        RoundedRectangle(cornerRadius: 19, style: .continuous)
            .fill(DevRoomDesignTokens.shirtColor(profile.shirtColor))
            .frame(width: 66, height: 46)
            .offset(y: isTyping ? 26 : 24)
    }

    private var head: some View {
        Circle()
            .fill(DevRoomDesignTokens.skinColor(profile.skinTone))
            .frame(width: 62, height: 58)
            .offset(y: isTyping ? -21 : -23)
    }

    @ViewBuilder
    private var hair: some View {
        switch profile.hairStyle {
        case .cropped:
            Capsule()
                .fill(DevRoomDesignTokens.hairColor(profile.hairColor))
                .frame(width: 50, height: 18)
                .offset(x: -2, y: isTyping ? -43 : -45)
        case .sidePart:
            HStack(spacing: -6) {
                Capsule()
                    .frame(width: 33, height: 19)
                Capsule()
                    .frame(width: 23, height: 15)
            }
            .foregroundStyle(DevRoomDesignTokens.hairColor(profile.hairColor))
            .rotationEffect(.degrees(-7))
            .offset(x: -1, y: isTyping ? -44 : -46)
        case .wavy:
            HStack(spacing: -7) {
                Circle().frame(width: 26, height: 22)
                Circle().frame(width: 27, height: 25)
                Circle().frame(width: 24, height: 21)
            }
            .foregroundStyle(DevRoomDesignTokens.hairColor(profile.hairColor))
            .offset(y: isTyping ? -43 : -45)
        case .bob:
            RoundedRectangle(cornerRadius: 4)
                .fill(DevRoomDesignTokens.hairColor(profile.hairColor))
                .frame(width: 56, height: 31)
                .offset(y: isTyping ? -35 : -37)
                .mask(alignment: .top) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .frame(width: 56, height: 26)
                }
        case .bun:
            ZStack(alignment: .topTrailing) {
                Capsule()
                    .frame(width: 49, height: 20)
                Circle()
                    .frame(width: 19, height: 19)
                    .offset(x: 20, y: -9)
            }
            .foregroundStyle(DevRoomDesignTokens.hairColor(profile.hairColor))
            .offset(x: -2, y: isTyping ? -43 : -45)
        case .flatTop:
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(DevRoomDesignTokens.hairColor(profile.hairColor))
                .frame(width: 51, height: 19)
                .offset(y: isTyping ? -44 : -46)
        }
    }

    private var eyes: some View {
        HStack(spacing: 16) {
            Capsule()
                .frame(width: 6, height: isBlinking ? 1 : 7)
            Capsule()
                .frame(width: 6, height: isBlinking ? 1 : 7)
        }
        .foregroundStyle(Color.black.opacity(0.70))
        .offset(y: isTyping ? -23 : -25)
    }

    private var mouth: some View {
        Capsule()
            .fill(Color.black.opacity(0.32))
            .frame(width: 11, height: 3)
            .offset(y: isTyping ? -8 : -10)
    }

    private var arms: some View {
        HStack(spacing: 31) {
            Capsule()
                .fill(DevRoomDesignTokens.skinColor(profile.skinTone))
                .frame(width: 12, height: 40)
                .rotationEffect(.degrees(isTyping ? 4 : -3), anchor: .top)
            Capsule()
                .fill(DevRoomDesignTokens.skinColor(profile.skinTone))
                .frame(width: 12, height: 40)
                .rotationEffect(.degrees(isTyping ? -4 : 3), anchor: .top)
        }
        .offset(y: 31)
    }

    @ViewBuilder
    private var accessory: some View {
        switch profile.accessory {
        case .none:
            EmptyView()
        case .glasses:
            HStack(spacing: 4) {
                Circle()
                    .stroke(Color.black.opacity(0.62), lineWidth: 2)
                    .frame(width: 17, height: 15)
                Rectangle()
                    .fill(Color.black.opacity(0.62))
                    .frame(width: 5, height: 2)
                Circle()
                    .stroke(Color.black.opacity(0.62), lineWidth: 2)
                    .frame(width: 17, height: 15)
            }
            .offset(y: isTyping ? -24 : -26)
        case .headphones:
            ZStack {
                Circle()
                    .trim(from: 0.53, to: 0.97)
                    .stroke(DevRoomDesignTokens.hairColor(profile.hairColor), lineWidth: 4)
                    .frame(width: 68, height: 64)
                HStack(spacing: 42) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .frame(width: 8, height: 17)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .frame(width: 8, height: 17)
                }
            }
            .foregroundStyle(DevRoomDesignTokens.hairColor(profile.hairColor))
            .offset(y: isTyping ? -22 : -24)
        }
    }
}
