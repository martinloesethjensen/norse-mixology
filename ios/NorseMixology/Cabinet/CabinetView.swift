import SwiftUI
import NorseMixologyCore

struct CabinetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaxonomyStore.self) private var taxonomyStore

    @State private var viewModel: CabinetViewModel?
    @State private var isPresentingAddSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Cabinet")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CabinetViewModel(modelContext: modelContext)
            }
        }
        .sheet(isPresented: $isPresentingAddSheet) {
            if let viewModel {
                AddIngredientView(cabinetViewModel: viewModel, taxonomyStore: taxonomyStore)
            }
        }
    }

    @ViewBuilder
    private func content(viewModel: CabinetViewModel) -> some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.groupedItems, id: \.category) { group in
                        Section(group.category) {
                            ForEach(group.items) { item in
                                CabinetItemRow(item: item)
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    viewModel.remove(group.items[index])
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)

                findRecipesButton
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "archivebox")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Your cabinet is empty")
                .font(.headline)
            Text("Add what's in your cabinet to get started")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Ingredient") { isPresentingAddSheet = true }
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }

    private var findRecipesButton: some View {
        Button {
            // Wired in Phase 3 (matching engine) / Phase 4 (results UI).
        } label: {
            Text("Find Recipes")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true)
        .padding()
        .help("Coming soon")
    }
}

private struct CabinetItemRow: View {
    let item: CabinetItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                Text(item.style)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            FlavorProfileIndicatorView(profile: item.flavorProfile)
        }
    }
}
