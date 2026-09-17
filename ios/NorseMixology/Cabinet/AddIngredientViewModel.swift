import Foundation
import NorseMixologyCore

@Observable
final class AddIngredientViewModel {
    enum Mode: String, CaseIterable {
        case search = "Search"
        case browse = "Browse"
    }

    let taxonomyStore: TaxonomyStore
    var mode: Mode = .search
    var searchText: String = ""

    init(taxonomyStore: TaxonomyStore) {
        self.taxonomyStore = taxonomyStore
    }

    var searchResults: [IngredientStyle] {
        IngredientSearch.search(searchText, in: taxonomyStore.categories)
    }

    func familyName(for style: IngredientStyle) -> String {
        taxonomyStore.familyNamesById[style.familyId] ?? ""
    }

    func categoryName(for style: IngredientStyle) -> String {
        taxonomyStore.categoryNamesById[style.categoryId] ?? ""
    }
}
