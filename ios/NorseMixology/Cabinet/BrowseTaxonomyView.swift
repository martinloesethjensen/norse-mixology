import SwiftUI
import NorseMixologyCore

struct BrowseTaxonomyView: View {
    let taxonomyStore: TaxonomyStore
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    var body: some View {
        List(taxonomyStore.categories) { category in
            NavigationLink(category.name) {
                FamilyListView(category: category, cabinetViewModel: cabinetViewModel, onSelectStyle: onSelectStyle)
            }
        }
        .listStyle(.plain)
    }
}

private struct FamilyListView: View {
    let category: IngredientCategory
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    var body: some View {
        List(category.families) { family in
            NavigationLink(family.name) {
                StyleListView(family: family, cabinetViewModel: cabinetViewModel, onSelectStyle: onSelectStyle)
            }
        }
        .listStyle(.plain)
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StyleListView: View {
    let family: IngredientFamily
    let cabinetViewModel: CabinetViewModel
    let onSelectStyle: (IngredientStyle) -> Void

    var body: some View {
        List(family.styles) { style in
            let inCabinet = cabinetViewModel.contains(styleId: style.id)
            IngredientRow(style: style, familyName: family.name, isInCabinet: inCabinet)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !inCabinet else { return }
                    onSelectStyle(style)
                }
        }
        .listStyle(.plain)
        .navigationTitle(family.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
