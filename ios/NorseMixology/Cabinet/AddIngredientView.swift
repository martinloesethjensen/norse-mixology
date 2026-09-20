import SwiftUI
import NorseMixologyCore

struct AddIngredientView: View {
    @Environment(\.dismiss) private var dismiss
    let cabinetViewModel: CabinetViewModel
    let taxonomyStore: TaxonomyStore

    @State private var viewModel: AddIngredientViewModel
    @State private var styleForConfirmation: IngredientStyle?
    @State private var duplicateTaps = 0

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
                        Text(mode.title).tag(mode)
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
            .dsScreenBackground()
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
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .padding(12)
                .frame(minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DesignTokens.surface))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
                .padding(.horizontal)

            if viewModel.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                Spacer()
                Text("Search by ingredient, style, or brand name")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                Spacer()
            } else {
                List(viewModel.searchResults) { style in
                    let inCabinet = cabinetViewModel.contains(styleId: style.id)
                    Button {
                        if inCabinet {
                            duplicateTaps += 1
                        } else {
                            styleForConfirmation = style
                        }
                    } label: {
                        IngredientRow(style: style, familyName: viewModel.familyName(for: style), isInCabinet: inCabinet)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(DesignTokens.surface)
                }
                .listStyle(.plain)
                .dsListBackground()
                .transientNotice("Already in your cabinet", trigger: duplicateTaps)
            }
        }
    }
}
