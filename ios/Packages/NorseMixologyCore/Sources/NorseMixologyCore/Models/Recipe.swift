import Foundation

public enum GlassType: String, Codable, Sendable {
    case coupe, rocks, highball, martini, collins, hurricane, flute, mug
    case wineGlass
}

public enum Method: String, Codable, Sendable {
    case shake, stir, build, blend, throwMethod = "throw"
}

public enum Difficulty: String, Codable, Sendable {
    case easy, medium, advanced
}

/// A single ingredient line within a `Recipe`. See `Data Model.md` §Recipe Data Model.
public struct RecipeIngredient: Codable, Equatable, Sendable {
    public let ingredientStyleId: UUID
    public let amount: String
    public let preparation: String?
    public let isOptional: Bool
    public let substituteNotes: String?

    public init(
        ingredientStyleId: UUID,
        amount: String,
        preparation: String?,
        isOptional: Bool,
        substituteNotes: String?
    ) {
        self.ingredientStyleId = ingredientStyleId
        self.amount = amount
        self.preparation = preparation
        self.isOptional = isOptional
        self.substituteNotes = substituteNotes
    }
}

/// Bundled in `recipes.json`, seeded into local storage on first launch.
public struct Recipe: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let description: String
    public let glassType: GlassType
    public let method: Method
    public let ingredients: [RecipeIngredient]
    public let steps: [String]
    public let flavorProfile: FlavorProfile
    public let tags: [String]
    public let difficulty: Difficulty
    public let imageURL: String?

    public init(
        id: UUID,
        name: String,
        description: String,
        glassType: GlassType,
        method: Method,
        ingredients: [RecipeIngredient],
        steps: [String],
        flavorProfile: FlavorProfile,
        tags: [String],
        difficulty: Difficulty,
        imageURL: String?
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.glassType = glassType
        self.method = method
        self.ingredients = ingredients
        self.steps = steps
        self.flavorProfile = flavorProfile
        self.tags = tags
        self.difficulty = difficulty
        self.imageURL = imageURL
    }
}
