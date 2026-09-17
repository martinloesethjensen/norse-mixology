import Foundation

/// Flattened lookup tables over a parsed taxonomy — styles by id, and
/// family/category names by id. Built once and passed into the matching
/// engine rather than re-derived per recipe.
public struct TaxonomyIndex: Sendable {
    public let stylesById: [UUID: IngredientStyle]
    public let familyNamesById: [UUID: String]
    public let categoryNamesById: [UUID: String]

    public init(stylesById: [UUID: IngredientStyle], familyNamesById: [UUID: String], categoryNamesById: [UUID: String]) {
        self.stylesById = stylesById
        self.familyNamesById = familyNamesById
        self.categoryNamesById = categoryNamesById
    }

    public init(categories: [IngredientCategory]) {
        self.stylesById = IngredientTaxonomy.flattenStyles(categories)
        var familyNames: [UUID: String] = [:]
        var categoryNames: [UUID: String] = [:]
        for category in categories {
            categoryNames[category.id] = category.name
            for family in category.families {
                familyNames[family.id] = family.name
            }
        }
        self.familyNamesById = familyNames
        self.categoryNamesById = categoryNames
    }

    public func categoryName(for style: IngredientStyle) -> String {
        categoryNamesById[style.categoryId] ?? ""
    }

    public func familyName(for style: IngredientStyle) -> String {
        familyNamesById[style.familyId] ?? ""
    }
}
