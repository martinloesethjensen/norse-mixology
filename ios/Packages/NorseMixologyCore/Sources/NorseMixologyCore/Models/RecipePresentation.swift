import Foundation

// Presentation-facing logic for the Recipe Browser (Phase 4). Kept in the core
// package rather than in views so it can be unit-tested without a simulator and
// so the Android port (Phase 9) can mirror the same rules.

/// Match results partitioned into the three sections the Recipe Browser shows.
/// Order within each group is the engine's order (exact first, then score
/// descending), which this type never re-sorts.
public struct GroupedMatchResults: Equatable, Sendable {
    /// `matchType == .exact` — the cabinet covers every required ingredient.
    public let perfect: [RecipeMatchResult]
    /// Partial matches needing at most one substitution.
    public let almost: [RecipeMatchResult]
    /// Partial matches needing two or more substitutions.
    public let exploring: [RecipeMatchResult]

    public init(results: [RecipeMatchResult]) {
        var perfect: [RecipeMatchResult] = []
        var almost: [RecipeMatchResult] = []
        var exploring: [RecipeMatchResult] = []

        for result in results {
            if result.matchType == .exact {
                perfect.append(result)
            } else if result.substitutions.count <= 1 {
                almost.append(result)
            } else {
                exploring.append(result)
            }
        }

        self.perfect = perfect
        self.almost = almost
        self.exploring = exploring
    }

    public var isEmpty: Bool { perfect.isEmpty && almost.isEmpty && exploring.isEmpty }
}

/// What a recipe card's match badge should communicate. Results never include
/// recipes with unresolved required ingredients, so a card is either fully
/// covered or needs substitutions; the "unavailable" look is used for
/// individual ingredient rows (see `AvailabilityStatus`), not for whole cards.
public enum MatchBadgeState: Equatable, Sendable {
    case exact
    case substituted(count: Int)

    public init(result: RecipeMatchResult) {
        switch result.matchType {
        case .exact:
            self = .exact
        case .partial:
            self = .substituted(count: max(1, result.substitutions.count))
        }
    }

    public var label: String {
        switch self {
        case .exact: return "✓ All ingredients"
        case .substituted(let count): return count == 1 ? "1 sub needed" : "\(count) subs needed"
        }
    }
}

public enum AvailabilityStatus: Equatable, Sendable {
    /// The exact ingredient is in the cabinet.
    case exact
    /// A different ingredient from the cabinet stands in for it.
    case substituted
    /// Not in the cabinet and not substituted. Only optional/garnish
    /// ingredients can end up here — a missing required ingredient drops the
    /// recipe from the results entirely.
    case unavailable
}

/// One recipe ingredient line plus how the user's cabinet covers it.
public struct IngredientAvailability: Equatable, Sendable, Identifiable {
    /// Position in `recipe.ingredients` — unique even if a recipe lists the
    /// same style twice.
    public let id: Int
    public let ingredient: RecipeIngredient
    public let status: AvailabilityStatus
    public let substitution: SubstitutionDetail?
}

public enum RecipeAvailability {
    /// Resolves each ingredient of the matched recipe against the cabinet, in
    /// recipe order. A reported substitution wins over an exact style in the
    /// cabinet, because a user "accept" override can substitute even when the
    /// exact style is also owned.
    public static func rows(for result: RecipeMatchResult, cabinetStyleIds: Set<UUID>) -> [IngredientAvailability] {
        let substitutionByRequiredId = Dictionary(
            result.substitutions.map { ($0.required.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return result.recipe.ingredients.enumerated().map { position, ingredient in
            if let substitution = substitutionByRequiredId[ingredient.ingredientStyleId] {
                return IngredientAvailability(id: position, ingredient: ingredient, status: .substituted, substitution: substitution)
            }
            let status: AvailabilityStatus = cabinetStyleIds.contains(ingredient.ingredientStyleId) ? .exact : .unavailable
            return IngredientAvailability(id: position, ingredient: ingredient, status: status, substitution: nil)
        }
    }
}

// MARK: - Display names & symbols

public extension GlassType {
    var displayName: String {
        switch self {
        case .coupe: return "Coupe"
        case .rocks: return "Rocks"
        case .highball: return "Highball"
        case .martini: return "Martini"
        case .collins: return "Collins"
        case .hurricane: return "Hurricane"
        case .flute: return "Flute"
        case .mug: return "Mug"
        case .wineGlass: return "Wine glass"
        }
    }

    /// SF Symbol name. Phase 4 mapping: stemmed glasses → `wineglass`,
    /// rocks/old-fashioned → `cup.and.saucer`, tall glasses → `cylinder`,
    /// handled mugs → `mug`.
    var symbolName: String {
        switch self {
        case .coupe, .martini, .flute, .wineGlass: return "wineglass"
        case .rocks: return "cup.and.saucer"
        case .highball, .collins, .hurricane: return "cylinder"
        case .mug: return "mug"
        }
    }
}

public extension Method {
    var displayName: String {
        switch self {
        case .shake: return "Shake"
        case .stir: return "Stir"
        case .build: return "Build"
        case .blend: return "Blend"
        case .throwMethod: return "Throw"
        }
    }
}

public extension Difficulty {
    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .advanced: return "Advanced"
        }
    }
}
