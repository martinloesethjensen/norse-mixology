import Foundation

/// Cosine similarity over the 9 flavour dimensions — excludes `abv`, per
/// the Data Model spec.
public enum FlavorSimilarity {
    public static func cosine(_ a: FlavorProfile, _ b: FlavorProfile) -> Double {
        let pairs: [(Double, Double)] = [
            (a.sweetness, b.sweetness), (a.bitterness, b.bitterness), (a.smokiness, b.smokiness),
            (a.citrus, b.citrus), (a.floral, b.floral), (a.spice, b.spice),
            (a.herbal, b.herbal), (a.fruity, b.fruity), (a.oaky, b.oaky),
        ]
        let dot = pairs.reduce(0.0) { $0 + $1.0 * $1.1 }
        let magA = (pairs.reduce(0.0) { $0 + $1.0 * $1.0 }).squareRoot()
        let magB = (pairs.reduce(0.0) { $0 + $1.1 * $1.1 }).squareRoot()
        guard magA > 0, magB > 0 else { return 0 }
        return dot / (magA * magB)
    }
}

/// Tier 3 curated substitutes — different family, same functional role,
/// which the same-family cosine fallback would never surface on its own.
/// Looked up by style name (stable across regenerations of the taxonomy's
/// deterministic ids) and resolved against the loaded taxonomy at match time.
public struct CuratedSubstitutionRule: Sendable {
    public let requiredStyleName: String
    public let substituteStyleName: String
    public let baseQuality: Double
}

public enum CuratedSubstitutions {
    public static let all: [CuratedSubstitutionRule] = [
        .init(requiredStyleName: "Dry Vermouth", substituteStyleName: "Fino Sherry", baseQuality: 0.6),
        .init(requiredStyleName: "Sweet/Rosso Vermouth", substituteStyleName: "Ruby Port", baseQuality: 0.55),
        .init(requiredStyleName: "Orgeat", substituteStyleName: "Amaretto", baseQuality: 0.55),
        .init(requiredStyleName: "Coffee Liqueur", substituteStyleName: "Hazelnut Liqueur", baseQuality: 0.5),
        .init(requiredStyleName: "Mezcal", substituteStyleName: "Scotch Single Malt (Islay)", baseQuality: 0.5),
    ]

    /// Bidirectional table keyed by required style id, candidates in rule order.
    public static func table(index: TaxonomyIndex) -> [UUID: [(substituteId: UUID, baseQuality: Double)]] {
        let stylesByName = Dictionary(uniqueKeysWithValues: index.stylesById.values.map { ($0.name, $0) })
        var result: [UUID: [(UUID, Double)]] = [:]
        for rule in all {
            guard let required = stylesByName[rule.requiredStyleName],
                  let substitute = stylesByName[rule.substituteStyleName] else { continue }
            result[required.id, default: []].append((substitute.id, rule.baseQuality))
            result[substitute.id, default: []].append((required.id, rule.baseQuality))
        }
        return result
    }
}

/// Generates human-readable substitution notes and presentation-only ratio hints.
public enum SubstitutionNote {
    private struct Dimension {
        let moreAdjective: String
        let lessAdjective: String
        let value: (FlavorProfile) -> Double
    }

    private static let dimensions: [Dimension] = [
        .init(moreAdjective: "sweeter", lessAdjective: "drier", value: { $0.sweetness }),
        .init(moreAdjective: "more bitter", lessAdjective: "less bitter", value: { $0.bitterness }),
        .init(moreAdjective: "smokier", lessAdjective: "less smoky", value: { $0.smokiness }),
        .init(moreAdjective: "more citrusy", lessAdjective: "less citrusy", value: { $0.citrus }),
        .init(moreAdjective: "more floral", lessAdjective: "less floral", value: { $0.floral }),
        .init(moreAdjective: "spicier", lessAdjective: "milder", value: { $0.spice }),
        .init(moreAdjective: "more herbal", lessAdjective: "less herbal", value: { $0.herbal }),
        .init(moreAdjective: "fruitier", lessAdjective: "less fruity", value: { $0.fruity }),
        .init(moreAdjective: "oakier", lessAdjective: "less oaky", value: { $0.oaky }),
    ]

    /// A minimum delta before a dimension is worth mentioning.
    private static let significanceThreshold = 0.05

    public static func generate(required: IngredientStyle, substitute: IngredientStyle) -> String {
        let deltas = dimensions
            .map { dim in (dim, dim.value(substitute.flavorProfile) - dim.value(required.flavorProfile)) }
            .filter { abs($0.1) >= significanceThreshold }
            .sorted { abs($0.1) > abs($1.1) }

        guard !deltas.isEmpty else {
            return "\(substitute.name) is a close match for \(required.name) — the cocktail should taste very similar."
        }

        let top = Array(deltas.prefix(2))
        let adjectives = top.map { $0.1 >= 0 ? $0.0.moreAdjective : $0.0.lessAdjective }
        let adjectivePhrase = adjectives.count == 1 ? adjectives[0] : "\(adjectives[0]) and \(adjectives[1])"

        // Prefer the second-ranked dimension for the summary clause when there is
        // one — it tends to read as the more natural "the drink will be ___"
        // descriptor (e.g. sweetness -> "drier"/"sweeter") rather than repeating
        // the lead dimension verbatim.
        let (effectDim, effectDelta) = top.count > 1 ? top[1] : top[0]
        let effect = effectDelta >= 0 ? effectDim.moreAdjective : effectDim.lessAdjective

        return "\(substitute.name) is \(adjectivePhrase) than \(required.name) — the cocktail will be \(effect)."
    }

    /// Presentation-only — never affects `matchScore`.
    public static func ratioHint(role: IngredientRole, required: IngredientStyle, substitute: IngredientStyle) -> String? {
        guard role == .sweetenerSour else { return nil }
        let delta = substitute.flavorProfile.sweetness - required.flavorProfile.sweetness
        if delta >= 0.2 { return "It's noticeably sweeter — try using about 25% less." }
        if delta <= -0.2 { return "It's noticeably less sweet — you may want to use a bit more." }
        return nil
    }
}
