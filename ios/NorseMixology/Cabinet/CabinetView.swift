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
    @State private var detailItem: CabinetItem?
    @Environment(ShoppingListViewModel.self) private var shopping
    /// Remembered across launches.
    @SceneStorage("cabinet.segment") private var segmentRaw = CabinetSegment.cabinet.rawValue

    private enum CabinetSegment: String {
        case cabinet, shopping
    }

    private var segment: Binding<CabinetSegment> {
        Binding(
            get: { CabinetSegment(rawValue: segmentRaw) ?? .cabinet },
            set: { segmentRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Show", selection: segment) {
                    Text("Cabinet").tag(CabinetSegment.cabinet)
                    Text("Shopping list (\(shopping.items.count))").tag(CabinetSegment.shopping)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch segment.wrappedValue {
                case .cabinet:
                    content(viewModel: viewModel)
                case .shopping:
                    ShoppingListView()
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .dsScreenBackground()
            .navigationTitle("Cabinet")
            .toolbar {
                if segment.wrappedValue == .cabinet {
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
        }
        .onAppear {
            viewModel.refresh()
            // Keeps the segment's count honest if a bottle reached the cabinet another way.
            shopping.pruneOwned(cabinetStyleIds: Set(viewModel.items.map(\.ingredientStyleId)))
        }
        .onChange(of: Set(viewModel.items.map(\.ingredientStyleId))) { _, owned in
            shopping.pruneOwned(cabinetStyleIds: owned)
        }
        .sheet(item: $detailItem) { item in
            IngredientDetailView(title: item.displayName, subtitle: item.family, profile: item.flavorProfile)
        }
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
                                Button { detailItem = item } label: {
                                    CabinetItemRow(item: item)
                                }
                                .buttonStyle(.plain)
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
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                if item.style != item.displayName {
                    Text(item.style)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            FlavorNoteChips(profile: item.flavorProfile)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the full flavour profile")
    }
}
