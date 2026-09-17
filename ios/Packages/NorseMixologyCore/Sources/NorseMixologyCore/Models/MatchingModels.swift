import Foundation

/// The functional role an ingredient plays within a recipe, used to weight
/// its contribution to `matchScore`. Not stored in `RecipeIngredient` (the
/// Data Model's Recipe schema has no role field) — derived at match time
/// by `RoleDerivation` from the ingredient's taxonomy category/family and,
/// for spirits, its amount relative to the recipe's other spirits. See
/// `RoleDerivation` for the exact derivation both platforms must replicate.
public enum IngredientRole: String, Codable, CaseIterable, Sendable {
    case base, modifier, sweetenerSour, bittersMixer, accent, garnish

    /// Default weights from the Data Model's "Matching Score & Strictness" spec.
    public var defaultWeight: Double {
        switch self {
        case .base: return 1.0
        case .modifier: return 0.8
        case .sweetenerSour: return 0.6
        case .bittersMixer: return 0.4
        case .accent: return 0.3
        case .garnish: return 0.1
        }
    }
}

/// Strictness and weighting knobs for the matching engine, plus user
/// accept/reject overrides. `roleWeights` is keyed by `IngredientRole.rawValue`
/// (rather than the enum itself) to keep JSON encoding a plain object.
public struct MatchPreferences: Codable, Equatable, Sendable {
    public var strictness: Double
    public var roleWeights: [String: Double]
    /// requiredStyleId -> a substitute styleId the user has told us to accept at quality 1.0.
    public var acceptOverrides: [UUID: UUID]
    /// requiredStyleId -> substitute styleIds the user has told us are never acceptable.
    public var rejectOverrides: [UUID: Set<UUID>]

    public init(
        strictness: Double,
        roleWeights: [String: Double],
        acceptOverrides: [UUID: UUID] = [:],
        rejectOverrides: [UUID: Set<UUID>] = [:]
    ) {
        self.strictness = strictness
        self.roleWeights = roleWeights
        self.acceptOverrides = acceptOverrides
        self.rejectOverrides = rejectOverrides
    }

    public static let `default` = MatchPreferences(
        strictness: 0.5,
        roleWeights: Dictionary(uniqueKeysWithValues: IngredientRole.allCases.map { ($0.rawValue, $0.defaultWeight) })
    )

    public func weight(for role: IngredientRole) -> Double {
        roleWeights[role.rawValue] ?? role.defaultWeight
    }

    /// `threshold = 0.45 + strictness * 0.40`, per the Data Model spec.
    public var similarityThreshold: Double {
        0.45 + strictness * 0.40
    }

    public func isRejected(substituteId: UUID, for requiredId: UUID) -> Bool {
        rejectOverrides[requiredId]?.contains(substituteId) ?? false
    }
}

public enum MatchType: String, Codable, Sendable {
    case exact, partial
}

/// One resolved substitution within a `RecipeMatchResult` — only present
/// when a different style than the one the recipe calls for was used.
public struct SubstitutionDetail: Codable, Equatable, Sendable {
    public let required: IngredientStyle
    public let substitute: IngredientStyle
    public let similarityScore: Double
    public let note: String
    public let ratioHint: String?

    public init(required: IngredientStyle, substitute: IngredientStyle, similarityScore: Double, note: String, ratioHint: String?) {
        self.required = required
        self.substitute = substitute
        self.similarityScore = similarityScore
        self.note = note
        self.ratioHint = ratioHint
    }
}

public struct RecipeMatchResult: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { recipe.id }
    public let recipe: Recipe
    public let matchScore: Double
    public let matchType: MatchType
    public let substitutions: [SubstitutionDetail]

    public init(recipe: Recipe, matchScore: Double, matchType: MatchType, substitutions: [SubstitutionDetail]) {
        self.recipe = recipe
        self.matchScore = matchScore
        self.matchType = matchType
        self.substitutions = substitutions
    }
}
