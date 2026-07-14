import SwiftUI

struct GitLabAvatarGroup: View {
    let participants: [GitLabWorkItemParticipant]

    private let maximumVisibleCount = 3

    var body: some View {
        HStack(spacing: -6) {
            ForEach(Array(participants.prefix(maximumVisibleCount).enumerated()), id: \.offset) { _, participant in
                avatar(for: participant)
            }

            if participants.count > maximumVisibleCount {
                Text("+\(participants.count - maximumVisibleCount)")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(.tertiary, in: Circle())
                    .overlay(Circle().strokeBorder(GitLabDesignTokens.borderSubtle))
                    .accessibilityLabel("\(participants.count - maximumVisibleCount) more participants")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityNames)
    }

    private func avatar(for participant: GitLabWorkItemParticipant) -> some View {
        AsyncImage(url: participant.avatarURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            default:
                Text(initials(for: participant.name))
                    .font(.caption2.weight(.semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.accentColor.opacity(0.14))
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(GitLabDesignTokens.surfacePrimary, lineWidth: 2))
        .accessibilityHidden(true)
    }

    private func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? "?" : value.uppercased()
    }

    private var accessibilityNames: String {
        let names = participants.map(\.name).joined(separator: ", ")
        return names.isEmpty ? "No participants" : "Participants: \(names)"
    }
}

#Preview {
    GitLabAvatarGroup(
        participants: [
            GitLabWorkItemParticipant(name: "Octo Cat", avatarURL: nil),
            GitLabWorkItemParticipant(name: "Review User", avatarURL: nil),
            GitLabWorkItemParticipant(name: "Build Bot", avatarURL: nil),
            GitLabWorkItemParticipant(name: "Release Manager", avatarURL: nil)
        ]
    )
    .padding()
}

