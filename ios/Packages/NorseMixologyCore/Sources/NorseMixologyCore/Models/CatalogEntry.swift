import Foundation

/// How far a catalog recipe is from makeable with the current cabinet.
public enum AvailabilityTier: CaseIterable, Sendable {
    case ready, missing1, missing2, missing3Plus
}

/// One catalog recipe evaluated against the cabinet (Recipe Catalog Browse spec §2).
public struct CatalogEntry: Identifiable, Equatable, Sendable {
    public var id: UUID { recipe.id }
    public let recipe: Recipe
    /// The engine's own result — non-nil exactly when the recipe appears in "Can make".
    public let match: RecipeMatchResult?
    /// Ingredients a cabinet item stands in for — reported even when the recipe
    /// isn't makeable yet, so the detail screen can show them as substituted.
    public let substitutions: [SubstitutionDetail]
    /// Required ingredients nothing in the cabinet can cover, in recipe order, no duplicates.
    public let missing: [IngredientStyle]

    public init(recipe: Recipe, match: RecipeMatchResult?, substitutions: [SubstitutionDetail], missing: [IngredientStyle]) {
        self.recipe = recipe
        self.match = match
        self.substitutions = substitutions
        self.missing = missing
    }

    public var tier: AvailabilityTier {
        if match != nil { return .ready }
        switch missing.count {
        case 0, 1: return .missing1 // 0 only via CatalogAvailability's invariant guard — never Ready
        case 2: return .missing2
        default: return .missing3Plus
        }
    }
}
