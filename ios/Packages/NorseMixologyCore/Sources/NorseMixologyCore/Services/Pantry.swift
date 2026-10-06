import Foundation

/// Persists the chosen `PantryStaple`s in `UserDefaults` as their raw values.
/// Unknown values (a staple removed in a later version) are dropped on load
/// rather than discarding the whole pantry. `defaults` is injected for tests,
/// like `TasteProfileStore`.
public enum PantryStore {
    private static let key = "com.norsemixology.pantryStaples"

    public static func load(defaults: UserDefaults = .standard) -> Set<PantryStaple> {
        let raw = defaults.stringArray(forKey: key) ?? []
        return Set(raw.compactMap(PantryStaple.init(rawValue:)))
    }

    public static func save(_ staples: Set<PantryStaple>, defaults: UserDefaults = .standard) {
        defaults.set(staples.map(\.rawValue).sorted(), forKey: key)
    }
}

/// Turns pantry staples into what the matcher understands: cabinet items.
/// The matching engine, `CatalogAvailability` and `BuyNextRanking` are not
/// changed — they are simply given the cabinet plus the pantry.
public enum Pantry {
    /// Catalog style ids the staples cover.
    public static func styleIds(for staples: Set<PantryStaple>, index: TaxonomyIndex) -> Set<UUID> {
        guard !staples.isEmpty else { return [] }
        let names = Set(staples.flatMap(\.styleNames))
        return Set(index.stylesById.values.filter { names.contains($0.name) }.map(\.id))
    }

    /// The cabinet followed by an unsaved `CabinetItem` for every pantry style
    /// it doesn't already hold, in name order. The extra items are never
    /// inserted into SwiftData.
    public static func effectiveCabinet(_ cabinet: [CabinetItem], staples: Set<PantryStaple>, index: TaxonomyIndex) -> [CabinetItem] {
        let owned = Set(cabinet.map(\.ingredientStyleId))
        let extras = styleIds(for: staples, index: index)
            .subtracting(owned)
            .compactMap { index.stylesById[$0] }
            .sorted { $0.name < $1.name }
            .map { CabinetItem.make(from: $0, index: index) }
        return cabinet + extras
    }
}
