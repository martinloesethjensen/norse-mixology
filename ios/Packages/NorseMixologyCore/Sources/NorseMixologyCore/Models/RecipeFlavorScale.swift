import Foundation

/// Puts a recipe's flavour scores on the same footing as an ingredient's.
///
/// A recipe is a blend of several ingredients plus dilution, so its scores sit
/// well below any single ingredient's. Read against the ingredient thresholds
/// most recipes would show no note at all. Each axis is therefore divided by
/// the highest score any catalog recipe has on that axis: 1.0 means "as
/// strongly as this catalog gets", and the usual note thresholds then apply.
public struct RecipeFlavorScale: Sendable {
    /// A near-empty axis (the catalog has almost no smoky drinks) must not turn noise into a note.
    public static let minimumMaximum = 0.2

    private let maxima: [FlavorAxis: Double]

    public init(recipes: [Recipe]) {
        var maxima: [FlavorAxis: Double] = [:]
        for axis in FlavorAxis.allCases {
            let highest = recipes.map { axis.value(in: $0.flavorProfile) }.max() ?? 0
            maxima[axis] = max(highest, Self.minimumMaximum)
        }
        self.maxima = maxima
    }

    /// The five noted axes rescaled to 0…1 against the catalog; all other fields unchanged.
    public func relative(_ profile: FlavorProfile) -> FlavorProfile {
        func scaled(_ axis: FlavorAxis) -> Double {
            min(1, axis.value(in: profile) / (maxima[axis] ?? Self.minimumMaximum))
        }
        return FlavorProfile(
            sweetness: scaled(.sweet), bitterness: scaled(.bitter), smokiness: scaled(.smoky),
            citrus: scaled(.citrus), floral: profile.floral, spice: profile.spice, herbal: scaled(.herbal),
            fruity: profile.fruity, oaky: profile.oaky, abv: profile.abv
        )
    }
}
