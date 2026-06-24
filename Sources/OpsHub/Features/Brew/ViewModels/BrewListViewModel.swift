import Foundation

@MainActor
final class BrewListViewModel: ObservableObject {
    @Published private(set) var packages: [BrewPackage] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let service: any BrewServicing

    init(service: any BrewServicing = BrewService()) {
        self.service = service
    }

    func loadPackages() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            packages = try await service.listInstalledPackages()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
