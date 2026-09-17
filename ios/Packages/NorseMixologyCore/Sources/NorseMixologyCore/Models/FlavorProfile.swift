import Foundation

/// Normalised 0.0–1.0 flavour dimensions used for substitution similarity
/// (see `Data Model.md` §Flavour Profile). `abv` is informational only —
/// it is excluded from the cosine similarity calculation.
public struct FlavorProfile: Codable, Equatable, Hashable, Sendable {
    public var sweetness: Double
    public var bitterness: Double
    public var smokiness: Double
    public var citrus: Double
    public var floral: Double
    public var spice: Double
    public var herbal: Double
    public var fruity: Double
    public var oaky: Double
    public var abv: Double

    public init(
        sweetness: Double,
        bitterness: Double,
        smokiness: Double,
        citrus: Double,
        floral: Double,
        spice: Double,
        herbal: Double,
        fruity: Double,
        oaky: Double,
        abv: Double
    ) {
        self.sweetness = sweetness
        self.bitterness = bitterness
        self.smokiness = smokiness
        self.citrus = citrus
        self.floral = floral
        self.spice = spice
        self.herbal = herbal
        self.fruity = fruity
        self.oaky = oaky
        self.abv = abv
    }
}
