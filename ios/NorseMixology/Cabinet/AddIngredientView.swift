import SwiftUI
import NorseMixologyCore

struct AddIngredientView: View {
    @Environment(\.dismiss) private var dismiss
    let cabinetViewModel: CabinetViewModel
    let taxonomyStore: TaxonomyStore

    @State private var viewModel: AddIngredientViewModel
    @State private var styleForConfirmation: IngredientStyle?

    init(cabinetViewModel: CabinetViewModel, taxonomyStore: TaxonomyStore) {
        self.cabinetViewModel = cabinetViewModel
        self.taxonomyStore = taxonomyStore
        _viewModel = State(initialValue: AddIngredientViewModel(taxonomyStore: taxonomyStore))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: Bindable(viewModel).mode) {
                    ForEach(AddIngredientViewModel.Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch viewModel.mode {
                case .search:
                    searchView
                case .browse:
                    BrowseTaxonomyView(taxonomyStore: taxonomyStore, cabinetViewModel: cabinetViewModel) { style in
                        styleForConfirmation = style
                    }
                }
            }
            .navigationTitle("Add Ingredient")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(item: $styleForConfirmation) { style in
            AddIngredientConfirmationView(style: style, cabinetViewModel: cabinetViewModel, taxonomyStore: taxonomyStore) {
                styleForConfirmation = nil
                dismiss()
            }
        }
    }

    private var searchView: some View {
        VStack {
            TextField("Search ingredients or brands", text: Bindable(viewModel).searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)

            if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                Text("Search by ingredient, style, or brand name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(viewModel.searchResults) { style in
                    let inCabinet = cabinetViewModel.contains(styleId: style.id)
                    IngredientRow(style: style, familyName: viewModel.familyName(for: style), isInCabinet: inCabinet)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard !inCabinet else { return }
                            styleForConfirmation = style
                        }
                }
                .listStyle(.plain)
            }
        }
    }
}
