import Foundation

/// A coarse, screen-reader-friendly reading of a 0…1 flavour score.
public enum FlavorLevel: String, Equatable, Sendable {
    case low, medium, high

    public init(value: Double) {
        switch value {
        case ..<0.34: self = .low
        case ..<0.67: self = .medium
        default: self = .high
        }
    }
}

public extension FlavorProfile {
    /// The five dimensions the flavour indicator shows, described in words,
    /// e.g. "Sweetness: high, Bitterness: low, Smokiness: low, Citrus: medium, Herbal: high".
    var accessibilitySummary: String {
        [
            ("Sweetness", sweetness), ("Bitterness", bitterness), ("Smokiness", smokiness),
            ("Citrus", citrus), ("Herbal", herbal),
        ]
        .map { "\($0.0): \(FlavorLevel(value: $0.1).rawValue)" }
        .joined(separator: ", ")
    }
}
