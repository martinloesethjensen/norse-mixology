import SwiftUI
import NorseMixologyCore

@Observable
final class AddIngredientViewModel {
    enum Mode: CaseIterable {
        case search, browse

        var title: LocalizedStringKey {
            switch self {
            case .search: return "Search"
            case .browse: return "Browse"
            }
        }
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
