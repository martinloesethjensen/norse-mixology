import Foundation

/// Top of the ingredient hierarchy (e.g. Spirit, Liqueur, Mixer).
/// See `Data Model.md` §Ingredient Hierarchy.
public struct IngredientCategory: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let families: [IngredientFamily]

    public init(id: UUID, name: String, families: [IngredientFamily]) {
        self.id = id
        self.name = name
        self.families = families
    }
}

/// Middle of the hierarchy (e.g. Gin, Rum, Whiskey).
public struct IngredientFamily: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let categoryId: UUID
    public let styles: [IngredientStyle]

    public init(id: UUID, name: String, categoryId: UUID, styles: [IngredientStyle]) {
        self.id = id
        self.name = name
        self.categoryId = categoryId
        self.styles = styles
    }
}

/// Leaf of the hierarchy (e.g. London Dry Gin) — the level a cabinet item or
/// recipe ingredient actually references.
public struct IngredientStyle: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let familyId: UUID
    public let categoryId: UUID
    public let exampleBrands: [String]
    public let flavorProfile: FlavorProfile
    public let abvMin: Double
    public let abvMax: Double

    public init(
        id: UUID,
        name: String,
        familyId: UUID,
        categoryId: UUID,
        exampleBrands: [String],
        flavorProfile: FlavorProfile,
        abvMin: Double,
        abvMax: Double
    ) {
        self.id = id
        self.name = name
        self.familyId = familyId
        self.categoryId = categoryId
        self.exampleBrands = exampleBrands
        self.flavorProfile = flavorProfile
        self.abvMin = abvMin
        self.abvMax = abvMax
    }
}
