import SwiftUI

struct BrewListView: View {
    @StateObject private var viewModel = BrewViewModel()
    @State private var updatingPackageIDs = Set<BrewPackage.ID>()
    @State private var isShowingError = false
    @State private var isShowingUpdateAllConfirmation = false

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
        .confirmationDialog(
            "Update all outdated packages?",
            isPresented: $isShowingUpdateAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update All") {
                Task { await viewModel.updateAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Homebrew will upgrade all outdated formulae and casks.")
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
                .keyboardShortcut("r", modifiers: .command)
                Button("Check Outdated", systemImage: "checkmark.circle") {
                    Task { await viewModel.checkOutdated() }
                }
                Button("Update All", systemImage: "arrow.up.circle") {
                    isShowingUpdateAllConfirmation = true
                }
                .disabled(viewModel.outdatedCount == 0 || viewModel.isLoading)
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
    }

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(title: "Installed", value: "\(viewModel.installedCount)", systemImage: "shippingbox")
            SummaryCard(title: "Outdated", value: "\(viewModel.outdatedCount)", systemImage: "arrow.triangle.2.circlepath")
            SummaryCard(title: "Formulae", value: "\(viewModel.formulaCount)", systemImage: "flask")
            SummaryCard(title: "Casks", value: "\(viewModel.caskCount)", systemImage: "cup.and.saucer")
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
                    if updatingPackageIDs.contains(package.id) {
                        ProgressView()
                            .controlSize(.small)
                    } else if package.status == .outdated {
                        Button("Update") {
                            update(package)
                        }
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isLoading || !updatingPackageIDs.isEmpty)
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
        CommandLogPanel(
            logs: viewModel.commandLogs,
            isExpanded: $viewModel.isLogExpanded,
            onClear: viewModel.clearLogs
        )
        .frame(maxWidth: .infinity)
    }

    private func statusLabel(for package: BrewPackage) -> some View {
        let status: (title: String, systemImage: String, color: Color)

        switch package.status {
        case .outdated:
            status = ("Outdated", "exclamationmark.arrow.triangle.2.circlepath", .orange)
        case .updating:
            status = ("Updating", "arrow.triangle.2.circlepath", .blue)
        case .error:
            status = ("Update failed", "exclamationmark.circle", .red)
        case .upToDate:
            status = ("Up to date", "checkmark.circle", .green)
        }

        return Label(
            status.title,
            systemImage: status.systemImage
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            status.color.opacity(0.14),
            in: Capsule()
        )
    }

    private func update(_ package: BrewPackage) {
        updatingPackageIDs.insert(package.id)
        Task {
            await viewModel.updatePackage(package)
            updatingPackageIDs.remove(package.id)
        }
    }
}
