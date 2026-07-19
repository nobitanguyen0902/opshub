import SwiftUI

struct DevRoomWorkstation: View {
    let summary: DevRoomEmployeeSummary
    let animationEvent: DevRoomAnimationEvent?
    let isWindowActive: Bool
    let reduceMotion: Bool
    let onSelect: () -> Void

    @State private var pulse = false
    @State private var pulseTask: Task<Void, Never>?
    @State private var laptopGlow = false

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .top) {
                DevRoomEmployeeTag(summary: summary)
                    .frame(maxWidth: 220)

                DevRoomCharacterView(
                    employee: characterEmployee,
                    isActive: isWindowActive,
                    reduceMotion: reduceMotion
                )
                .offset(y: 46)

                workstationFurniture
                    .offset(y: 156)
            }
            .frame(maxWidth: .infinity, minHeight: 238)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .scaleEffect(pulse ? 1.025 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.employee.name), \(summary.total) task")
        .accessibilityHint("Mở danh sách task")
        .task(id: idleAnimationKey) {
            guard idleAnimationKey else {
                laptopGlow = false
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(Int(summary.employee.id.magnitude % 600)))
                while Task.isCancelled == false {
                    withAnimation(.easeInOut(duration: 0.45)) {
                        laptopGlow.toggle()
                    }
                    try await Task.sleep(for: .milliseconds(900))
                }
            } catch {
                laptopGlow = false
            }
        }
        .onChange(of: animationEvent?.generation) {
            guard isWindowActive,
                  reduceMotion == false,
                  animationEvent?.employeeIDs.contains(summary.employee.id) == true else {
                return
            }

            pulseTask?.cancel()
            withAnimation(.spring(duration: 0.28)) {
                pulse = true
            }
            pulseTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: .milliseconds(320))
                } catch {
                    return
                }

                guard Task.isCancelled == false else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    pulse = false
                }
            }
        }
        .onChange(of: isWindowActive) {
            guard isWindowActive == false else { return }
            cancelPulse()
        }
        .onChange(of: reduceMotion) {
            guard reduceMotion else { return }
            cancelPulse()
        }
        .onDisappear {
            cancelPulse()
            laptopGlow = false
        }
    }

    var characterEmployee: DevRoomEmployee {
        summary.employee
    }

    private var idleAnimationKey: Bool {
        isWindowActive && reduceMotion == false
    }

    private var workstationFurniture: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(DevRoomDesignTokens.officeFurnitureColor)
                .frame(width: 206, height: 12)

            HStack(spacing: 154) {
                Rectangle()
                    .fill(DevRoomDesignTokens.officeFurnitureColor)
                    .frame(width: 10, height: 54)
                Rectangle()
                    .fill(DevRoomDesignTokens.officeFurnitureColor)
                    .frame(width: 10, height: 54)
            }
            .offset(y: 8)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(DevRoomDesignTokens.officeLaptopColor)
                .frame(width: 68, height: 42)
                .overlay(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Color.black.opacity(0.2))
                        .frame(width: 82, height: 5)
                        .offset(y: 5)
                }
                .opacity(laptopGlow ? 1 : 0.78)
                .offset(x: -18, y: -38)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color(red: 0.83, green: 0.37, blue: 0.28))
                .frame(width: 16, height: 18)
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .stroke(Color.white.opacity(0.78), lineWidth: 2)
                        .frame(width: 8, height: 8)
                        .offset(x: 4, y: -2)
                }
                .offset(x: 72, y: -16)
        }
        .frame(width: 220, height: 72, alignment: .top)
    }

    private func cancelPulse() {
        pulseTask?.cancel()
        pulseTask = nil
        pulse = false
    }
}
