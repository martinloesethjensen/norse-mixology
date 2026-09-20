import SwiftUI
import NorseMixologyCore

struct BrowseTaxonomyView: View {
    let taxonomyStore: TaxonomyStore
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    var body: some View {
        List(taxonomyStore.categories) { category in
            NavigationLink {
                FamilyListView(category: category, cabinetViewModel: cabinetViewModel, onSelectStyle: onSelectStyle)
            } label: {
                Text(category.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .listRowBackground(DesignTokens.surface)
        }
        .listStyle(.plain)
        .dsListBackground()
    }
}

private struct FamilyListView: View {
    let category: IngredientCategory
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    var body: some View {
        List(category.families) { family in
            NavigationLink {
                StyleListView(family: family, cabinetViewModel: cabinetViewModel, onSelectStyle: onSelectStyle)
            } label: {
                Text(family.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
            }
            .listRowBackground(DesignTokens.surface)
        }
        .listStyle(.plain)
        .dsListBackground()
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StyleListView: View {
    let family: IngredientFamily
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    @State private var duplicateTaps = 0

    var body: some View {
        List(family.styles) { style in
            let inCabinet = cabinetViewModel.contains(styleId: style.id)
            Button {
                if inCabinet {
                    duplicateTaps += 1
                } else {
                    onSelectStyle(style)
                }
            } label: {
                IngredientRow(style: style, familyName: family.name, isInCabinet: inCabinet)
            }
            .buttonStyle(.plain)
            .listRowBackground(DesignTokens.surface)
        }
        .listStyle(.plain)
        .dsListBackground()
        .transientNotice("Already in your cabinet", trigger: duplicateTaps)
        .navigationTitle(family.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
