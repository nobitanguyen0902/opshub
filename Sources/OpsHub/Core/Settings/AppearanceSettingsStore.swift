import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }

    var description: String {
        switch self {
        case .system:
            "Automatically follows the operating system appearance."
        case .light:
            "Always use light mode."
        case .dark:
            "Always use dark mode."
        }
    }

    var systemImage: String {
        switch self {
        case .system:
            "circle.lefthalf.filled"
        case .light:
            "sun.max"
        case .dark:
            "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}

@MainActor
final class AppearanceSettingsStore: ObservableObject {
    static let themeKey = "appearance.theme"

    @Published private(set) var theme: AppTheme

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        theme = userDefaults.string(forKey: Self.themeKey)
            .flatMap(AppTheme.init(rawValue:)) ?? .system
    }

    func setTheme(_ theme: AppTheme) {
        guard self.theme != theme else {
            return
        }

        self.theme = theme
        userDefaults.set(theme.rawValue, forKey: Self.themeKey)
    }
}
