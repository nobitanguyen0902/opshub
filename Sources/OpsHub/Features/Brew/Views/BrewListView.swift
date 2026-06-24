import SwiftUI

struct BrewListView: View {
    @StateObject private var viewModel = BrewViewModel()
    @State private var updatingPackageNames = Set<String>()
    @State private var isShowingError = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            summaryCards
            searchAndFilter
            packageTable
            commandLog
        }
        .padding(20)
        .navigationTitle("Brew Manager")
        .task {
            await viewModel.loadPackages()
        }
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.08)
                    ProgressView("Running Homebrew command…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .ignoresSafeArea()
            }
        }
        .onChange(of: viewModel.errorMessage) { _, errorMessage in
            isShowingError = errorMessage != nil
        }
        .alert("Homebrew Error", isPresented: $isShowingError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Brew Manager")
                    .font(.largeTitle.bold())
                Text("Manage installed Homebrew formulae and casks.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await viewModel.loadPackages() }
                }
                Button("Check Outdated", systemImage: "checkmark.circle") {
                    Task { await viewModel.checkOutdated() }
                }
                Button("Update All", systemImage: "arrow.up.circle") {
                    Task { await viewModel.updateAll() }
                }
                .disabled(viewModel.outdatedCount == 0 || viewModel.isLoading)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Installed", count: viewModel.installedCount, icon: "shippingbox")
            SummaryCard(title: "Outdated", count: viewModel.outdatedCount, icon: "arrow.triangle.2.circlepath")
            SummaryCard(title: "Formulae", count: viewModel.formulaCount, icon: "flask")
            SummaryCard(title: "Casks", count: viewModel.caskCount, icon: "cup.and.saucer")
        }
    }

    private var searchAndFilter: some View {
        HStack(spacing: 16) {
            TextField("Search packages", text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)

            Picker("Package type", selection: $viewModel.selectedFilter) {
                Text("All").tag(BrewViewModel.Filter.all)
                Text("Formulae").tag(BrewViewModel.Filter.formulae)
                Text("Casks").tag(BrewViewModel.Filter.casks)
                Text("Outdated").tag(BrewViewModel.Filter.outdated)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
        }
    }

    @ViewBuilder
    private var packageTable: some View {
        if viewModel.packages.isEmpty && !viewModel.isLoading {
            ContentUnavailableView(
                "No Homebrew packages found",
                systemImage: "cup.and.saucer",
                description: Text("Install a package with Homebrew, then refresh this list.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.filteredPackages.isEmpty && !viewModel.isLoading {
            ContentUnavailableView.search(text: viewModel.searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(viewModel.filteredPackages) {
                TableColumn("Name") { package in
                    Text(package.name)
                        .fontWeight(.medium)
                }
                TableColumn("Type") { package in
                    Text(package.type == .formula ? "Formula" : "Cask")
                }
                TableColumn("Installed Version") { package in
                    Text(package.installedVersion)
                }
                TableColumn("Latest Version") { package in
                    Text(package.latestVersion)
                }
                TableColumn("Status") { package in
                    statusLabel(for: package)
                }
                TableColumn("Action") { package in
                    if updatingPackageNames.contains(package.name) {
                        ProgressView()
                            .controlSize(.small)
                    } else if package.status == .outdated {
                        Button("Update") {
                            update(package)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoading)
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var commandLog: some View {
        DisclosureGroup("Command Log", isExpanded: $viewModel.isLogExpanded) {
            ScrollView {
                Text(viewModel.commandLogs.isEmpty ? "No commands have been run yet." : viewModel.commandLogs.joined(separator: "\n"))
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(height: 110)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func statusLabel(for package: BrewPackage) -> some View {
        if package.status == .outdated {
            Label("Outdated", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                .foregroundStyle(.orange)
        } else {
            Label("Up to date", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
        }
    }

    private func update(_ package: BrewPackage) {
        updatingPackageNames.insert(package.name)
        Task {
            await viewModel.updatePackage(package)
            updatingPackageNames.remove(package.name)
        }
    }
}

private struct SummaryCard: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(.title2.bold())
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}
