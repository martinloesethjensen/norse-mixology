import SwiftUI
import NorseMixologyCore

struct CabinetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaxonomyStore.self) private var taxonomyStore

    @State private var viewModel: CabinetViewModel?
    @State private var isPresentingAddSheet = false
    @State private var matchResults: MatchResultsPayload?

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
            .navigationDestination(item: $matchResults) { payload in
                RecipeBrowserView(results: payload.results)
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

                findRecipesButton(viewModel: viewModel)
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

    private func findRecipesButton(viewModel: CabinetViewModel) -> some View {
        Button {
            matchResults = MatchResultsPayload(results: viewModel.findRecipes(taxonomyStore: taxonomyStore))
        } label: {
            Text("Find Recipes")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
    }
}

/// Wraps match results with a fresh identity per search so
/// `navigationDestination(item:)` (which requires `Hashable`) can be driven
/// without threading `Hashable` through the whole matching-result model graph.
struct MatchResultsPayload: Hashable {
    let id = UUID()
    let results: [RecipeMatchResult]

    static func == (lhs: MatchResultsPayload, rhs: MatchResultsPayload) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
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
