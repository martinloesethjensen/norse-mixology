import Foundation

/// Kitchen basics most people have without thinking of them as bar stock.
/// A chosen staple counts as owned when matching recipes, but is never stored
/// as a `CabinetItem`, so it doesn't appear in the Cabinet and is never
/// suggested by Buy next (see Pantry Staples spec §1).
///
/// Each staple covers catalog styles by name — stable across regenerations of
/// the taxonomy's deterministic ids. Names missing from the loaded catalog are
/// ignored, so a catalog change can't break a saved pantry.
public enum PantryStaple: String, CaseIterable, Sendable, Identifiable {
    case sugar, honey, eggs, sodaWater, lemonsAndLimes, oranges, salt

    public var id: String { rawValue }

    public var styleNames: [String] {
        switch self {
        case .sugar: return ["Simple Syrup", "Demerara Syrup", "Sugar Rim"]
        case .honey: return ["Honey Syrup"]
        case .eggs: return ["Egg White"]
        case .sodaWater: return ["Club Soda"]
        case .lemonsAndLimes: return ["Fresh Lemon", "Fresh Lime", "Lemon Juice", "Lime Juice", "Lemon Twist", "Lime Wedge"]
        case .oranges: return ["Fresh Orange", "Orange Juice", "Orange Wheel", "Orange Twist"]
        case .salt: return ["Kosher Salt Rim"]
        }
    }
}
