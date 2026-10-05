import Foundation

/// All recipes, bucketed for the All recipes view: Ready / Missing 1 / Missing 2 / Missing 3+.
/// Base order: Ready like the engine (exact first, then score, then name);
/// Missing tiers by missing count, then name. An active taste profile then
/// re-sorts within each tier (stable, so the base order breaks ties).
public struct GroupedAvailability: Equatable, Sendable {
    public let ready: [CatalogEntry]
    public let missing1: [CatalogEntry]
    public let missing2: [CatalogEntry]
    public let missing3Plus: [CatalogEntry]

    public static let empty = GroupedAvailability(entries: [], profile: .neutral)

    public init(entries: [CatalogEntry], profile: UserTasteProfile) {
        func byName(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            lhs.recipe.name.localizedStandardCompare(rhs.recipe.name) == .orderedAscending
        }
        func readyOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            let l = lhs.match, r = rhs.match
            if l?.matchType != r?.matchType { return l?.matchType == .exact }
            if l?.matchScore != r?.matchScore { return (l?.matchScore ?? 0) > (r?.matchScore ?? 0) }
            return byName(lhs, rhs)
        }
        func missingOrder(_ lhs: CatalogEntry, _ rhs: CatalogEntry) -> Bool {
            lhs.missing.count != rhs.missing.count ? lhs.missing.count < rhs.missing.count : byName(lhs, rhs)
        }
        func ranked(_ tier: AvailabilityTier, by order: (CatalogEntry, CatalogEntry) -> Bool) -> [CatalogEntry] {
            TasteRanking.sorted(entries.filter { $0.tier == tier }.sorted(by: order), toward: profile) { $0.recipe.flavorProfile }
        }
        self.init(
            ready: ranked(.ready, by: readyOrder),
            missing1: ranked(.missing1, by: missingOrder),
            missing2: ranked(.missing2, by: missingOrder),
            missing3Plus: ranked(.missing3Plus, by: missingOrder)
        )
    }

    private init(ready: [CatalogEntry], missing1: [CatalogEntry], missing2: [CatalogEntry], missing3Plus: [CatalogEntry]) {
        self.ready = ready
        self.missing1 = missing1
        self.missing2 = missing2
        self.missing3Plus = missing3Plus
    }

    public var isEmpty: Bool { ready.isEmpty && missing1.isEmpty && missing2.isEmpty && missing3Plus.isEmpty }

    public var allIds: [UUID] { (ready + missing1 + missing2 + missing3Plus).map(\.id) }

    public func entries(in tier: AvailabilityTier) -> [CatalogEntry] {
        switch tier {
        case .ready: return ready
        case .missing1: return missing1
        case .missing2: return missing2
        case .missing3Plus: return missing3Plus
        }
    }

    /// Keeps tiers and the order within them.
    public func filtered(by filter: RecipeFilter, index: TaxonomyIndex) -> GroupedAvailability {
        guard !filter.isEmpty else { return self }
        let keep = { (entry: CatalogEntry) in filter.matches(entry.recipe, index: index) }
        return GroupedAvailability(ready: ready.filter(keep), missing1: missing1.filter(keep),
                                   missing2: missing2.filter(keep), missing3Plus: missing3Plus.filter(keep))
    }
}

/// What the Recipes tab is showing — pure state so it is unit-testable
/// (the app target has no test target).
public struct RecipeBrowseState: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case canMake, all
    }

    public var mode: Mode
    public var filter: RecipeFilter

    public init(mode: Mode = .canMake, filter: RecipeFilter = RecipeFilter()) {
        self.mode = mode
        self.filter = filter
    }
}
