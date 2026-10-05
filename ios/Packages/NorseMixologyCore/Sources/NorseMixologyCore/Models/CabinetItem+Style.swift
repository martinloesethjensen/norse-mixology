import Foundation

public extension CabinetItem {
    /// A cabinet snapshot of a catalog style — the one place the cabinet's add
    /// flow and the shopping list's tick-off build cabinet items. A blank or
    /// whitespace-only brand counts as no brand.
    static func make(from style: IngredientStyle, index: TaxonomyIndex, brand: String? = nil, date: Date = Date()) -> CabinetItem {
        let trimmedBrand = brand?.trimmingCharacters(in: .whitespacesAndNewlines)
        let brandValue = (trimmedBrand?.isEmpty ?? true) ? nil : trimmedBrand
        return CabinetItem(
            ingredientStyleId: style.id,
            ingredientFamilyId: style.familyId,
            categoryId: style.categoryId,
            displayName: brandValue.map { "\($0) \(style.name)" } ?? style.name,
            brand: brandValue,
            style: style.name,
            family: index.familyName(for: style),
            category: index.categoryName(for: style),
            flavorProfile: style.flavorProfile,
            dateAdded: date
        )
    }
}
