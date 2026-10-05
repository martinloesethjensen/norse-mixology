import SwiftUI
import NorseMixologyCore

/// Every filter, grouped by kind. Changes apply immediately; "Clear" resets
/// filters (not the search text).
struct RecipeFilterSheet: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let options = viewModel.filterOptions
        NavigationStack {
            Form {
                section("Strength", RecipeFilter.Strength.allCases.map { RecipeFilter.Criterion.strength($0) })
                section("Base spirit", options.baseFamilies.map { RecipeFilter.Criterion.baseFamily($0.id) })
                section("Style", options.tags.map { RecipeFilter.Criterion.tag($0) })
                section("Glass", options.glassTypes.map { RecipeFilter.Criterion.glass($0) })
                section("Method", options.methods.map { RecipeFilter.Criterion.method($0) })
                section("Difficulty", options.difficulties.map { RecipeFilter.Criterion.difficulty($0) })
            }
            .dsListBackground()
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        for criterion in viewModel.browseState.filter.criteria {
                            viewModel.browseState.filter.remove(criterion)
                        }
                    }
                    .disabled(viewModel.browseState.filter.criteria.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ criteria: [RecipeFilter.Criterion]) -> some View {
        if !criteria.isEmpty {
            Section {
                ForEach(criteria, id: \.self) { row($0) }
            } header: {
                Text(title)
                    .dsText(.label)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .listRowBackground(DesignTokens.surface)
        }
    }

    private func row(_ criterion: RecipeFilter.Criterion) -> some View {
        let isOn = viewModel.browseState.filter.contains(criterion)
        return Button {
            viewModel.browseState.filter.toggle(criterion)
        } label: {
            HStack {
                Text(criterion.label(familyNamesById: viewModel.familyNamesById))
                    .dsText(.heading)
                    .fontWeight(.regular)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer()
                if isOn {
                    Image(systemName: "checkmark")
                        .foregroundStyle(DesignTokens.accent)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
