import Foundation

struct BrewPackage: Identifiable, Hashable, Sendable {
    let name: String
    let version: String
    let description: String

    var id: String { name }
}
