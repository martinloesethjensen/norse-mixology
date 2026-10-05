import SwiftUI
import SwiftData
import NorseMixologyCore

struct CabinetView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(RecipeBrowserViewModel.self) private var recipeBrowserViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Called after a fresh match has been run, so the host can show the results.
    let onFindRecipes: () -> Void

    @Environment(CabinetViewModel.self) private var viewModel
    @State private var isPresentingAddSheet = false

    var body: some View {
        NavigationStack {
            content(viewModel: viewModel)
            .dsScreenBackground()
            .navigationTitle("Cabinet")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingAddSheet = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .onAppear { viewModel.refresh() }
        .sheet(isPresented: $isPresentingAddSheet) {
            AddIngredientView(cabinetViewModel: viewModel, taxonomyStore: taxonomyStore)
        }
    }

    @ViewBuilder
    private func content(viewModel: CabinetViewModel) -> some View {
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label {
                    Text("Your cabinet is empty")
                } icon: {
                    FloatingIcon(systemName: "archivebox")
                }
            } description: {
                Text("Add what's in your cabinet to get started")
            } actions: {
                Button("Add Ingredient") { isPresentingAddSheet = true }
                    .buttonStyle(.dsPrimary)
                    .frame(maxWidth: 280)
            }
        } else {
            VStack(spacing: 0) {
                List {
                    ForEach(viewModel.groupedItems, id: \.category) { group in
                        Section {
                            ForEach(group.items) { item in
                                CabinetItemRow(item: item)
                                    .listRowBackground(DesignTokens.surface)
                                    .transition(reduceMotion ? .identity : .asymmetric(
                                        insertion: .scale(scale: 0.9).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                            }
                            .onDelete { offsets in
                                for index in offsets {
                                    viewModel.remove(group.items[index])
                                }
                            }
                        } header: {
                            Text(group.category)
                                .dsText(.label)
                                .textCase(.uppercase)
                                .tracking(0.6)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .dsListBackground()

                findRecipesButton
            }
        }
    }

    private var findRecipesButton: some View {
        Button {
            recipeBrowserViewModel.refresh(context: modelContext, taxonomyStore: taxonomyStore)
            onFindRecipes()
        } label: {
            Text("Find Recipes")
        }
        .buttonStyle(.dsPrimary)
        .frame(maxWidth: 560)
        .padding()
    }
}

private struct CabinetItemRow: View {
    let item: CabinetItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(item.style)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            Spacer()
            FlavorProfileIndicatorView(profile: item.flavorProfile)
        }
        .accessibilityElement(children: .combine)
    }
}
