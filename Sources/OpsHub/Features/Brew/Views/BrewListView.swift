import SwiftUI

struct BrewListView: View {
    @StateObject private var viewModel = BrewListViewModel()

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.packages.isEmpty {
                ProgressView("Loading Homebrew packages…")
            } else if let errorMessage = viewModel.errorMessage {
                ContentUnavailableView(
                    "Could not load Homebrew packages",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if viewModel.packages.isEmpty {
                ContentUnavailableView(
                    "No Homebrew packages found",
                    systemImage: "cup.and.saucer",
                    description: Text("Install a package with Homebrew, then refresh this list.")
                )
            } else {
                List(viewModel.packages) { package in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.name)
                            .font(.headline)
                        Text(package.version)
                            .foregroundStyle(.secondary)
                        Text(package.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Brew")
        .toolbar {
            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await viewModel.loadPackages() }
            }
            .disabled(viewModel.isLoading)
        }
        .task {
            await viewModel.loadPackages()
        }
    }
}
