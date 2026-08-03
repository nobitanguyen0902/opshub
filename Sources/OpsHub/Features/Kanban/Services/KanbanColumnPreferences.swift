import Foundation

final class KanbanColumnPreferences {
    static let collapsedKey = "kanban.collapsedColumns"

    var collapsedColumns: Set<KanbanColumn> {
        Set(userDefaults.stringArray(forKey: Self.collapsedKey)?.compactMap(KanbanColumn.init(rawValue:)) ?? [])
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func setCollapsed(_ collapsed: Bool, column: KanbanColumn) {
        var value = collapsedColumns
        if collapsed {
            value.insert(column)
        } else {
            value.remove(column)
        }
        userDefaults.set(value.map(\.rawValue).sorted(), forKey: Self.collapsedKey)
    }
}
