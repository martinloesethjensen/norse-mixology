import Foundation

/// Search + filter criteria for the Recipes tab (Recipe Catalog Browse spec §2).
/// Different kinds of criterion combine with AND; several values of one kind with OR.
public struct RecipeFilter: Equatable, Sendable {
    public enum Strength: String, CaseIterable, Sendable {
        case noABV, lowABV, regular

        public init(recipe: Recipe) {
            if recipe.tags.contains("no-abv") {
                self = .noABV
            } else if recipe.tags.contains("low-abv") {
                self = .lowABV
            } else {
                self = .regular
            }
        }

        public var displayName: String {
            switch self {
            case .noABV: return "No alcohol"
            case .lowABV: return "Low alcohol"
            case .regular: return "Regular"
            }
        }
    }

    /// One removable filter value — what a chip shows and what the filter sheet toggles.
    public enum Criterion: Hashable, Sendable {
        case tag(String)
        case strength(Strength)
        case baseFamily(UUID)
        case glass(GlassType)
        case method(Method)
        case difficulty(Difficulty)
    }

    /// Curated style tags offered in the filter UI; other catalog tags are ignored.
    public static let styleTags = ["sour", "tall", "spirit-forward", "refreshing", "tiki", "creamy", "sparkling", "bitter", "smoky", "dessert"]

    public var query: String = ""
    /// In the order the user added them, so chips don't jump around.
    public private(set) var criteria: [Criterion] = []

    public init() {}

    public var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    public var isEmpty: Bool { trimmedQuery.isEmpty && criteria.isEmpty }

    public func contains(_ criterion: Criterion) -> Bool { criteria.contains(criterion) }

    public mutating func toggle(_ criterion: Criterion) {
        if let position = criteria.firstIndex(of: criterion) {
            criteria.remove(at: position)
        } else {
            criteria.append(criterion)
        }
    }

    public mutating func remove(_ criterion: Criterion) {
        criteria.removeAll { $0 == criterion }
    }

    public mutating func clear() {
        query = ""
        criteria = []
    }

    public func matches(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        matchesQuery(recipe, index: index) && matchesCriteria(recipe, index: index)
    }

    /// Families of the ingredient(s) `RoleDerivation` treats as the recipe's base.
    public static func baseFamilyIds(of recipe: Recipe, index: TaxonomyIndex) -> Set<UUID> {
        Set(recipe.ingredients.compactMap { ingredient -> UUID? in
            guard let style = index.stylesById[ingredient.ingredientStyleId],
                  RoleDerivation.role(for: ingredient, style: style, in: recipe, index: index) == .base else { return nil }
            return style.familyId
        })
    }

    /// Case- and diacritic-insensitive substring match on the recipe name, then
    /// on each ingredient's style and family name.
    private func matchesQuery(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        let query = trimmedQuery
        guard !query.isEmpty else { return true }
        if recipe.name.localizedStandardContains(query) { return true }
        return recipe.ingredients.contains { ingredient in
            guard let style = index.stylesById[ingredient.ingredientStyleId] else { return false }
            return style.name.localizedStandardContains(query) || index.familyName(for: style).localizedStandardContains(query)
        }
    }

    private func matchesCriteria(_ recipe: Recipe, index: TaxonomyIndex) -> Bool {
        guard !criteria.isEmpty else { return true }
        var tags: Set<String> = []
        var strengths: Set<Strength> = []
        var families: Set<UUID> = []
        var glasses: Set<GlassType> = []
        var methods: Set<Method> = []
        var difficulties: Set<Difficulty> = []
        for criterion in criteria {
            switch criterion {
            case .tag(let tag): tags.insert(tag)
            case .strength(let strength): strengths.insert(strength)
            case .baseFamily(let id): families.insert(id)
            case .glass(let glass): glasses.insert(glass)
            case .method(let method): methods.insert(method)
            case .difficulty(let difficulty): difficulties.insert(difficulty)
            }
        }
        if !tags.isEmpty, tags.isDisjoint(with: recipe.tags) { return false }
        if !strengths.isEmpty, !strengths.contains(Strength(recipe: recipe)) { return false }
        if !families.isEmpty, families.isDisjoint(with: Self.baseFamilyIds(of: recipe, index: index)) { return false }
        if !glasses.isEmpty, !glasses.contains(recipe.glassType) { return false }
        if !methods.isEmpty, !methods.contains(recipe.method) { return false }
        if !difficulties.isEmpty, !difficulties.contains(recipe.difficulty) { return false }
        return true
    }
}

public struct FamilyOption: Hashable, Sendable {
    public let id: UUID
    public let name: String
}

/// The values the filter sheet offers — only ones present in the loaded catalog,
/// so new catalog values appear without an app update.
public struct RecipeFilterOptions: Equatable, Sendable {
    public let tags: [String]
    public let baseFamilies: [FamilyOption]
    public let glassTypes: [GlassType]
    public let methods: [Method]
    public let difficulties: [Difficulty]

    public static let empty = RecipeFilterOptions(recipes: [], index: TaxonomyIndex(categories: []))

    public init(recipes: [Recipe], index: TaxonomyIndex) {
        let presentTags = Set(recipes.flatMap(\.tags))
        tags = RecipeFilter.styleTags.filter(presentTags.contains)

        let familyIds = recipes.reduce(into: Set<UUID>()) { $0.formUnion(RecipeFilter.baseFamilyIds(of: $1, index: index)) }
        baseFamilies = familyIds
            .compactMap { id in index.familyNamesById[id].map { FamilyOption(id: id, name: $0) } }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        glassTypes = Set(recipes.map(\.glassType)).sorted { $0.displayName < $1.displayName }
        methods = Set(recipes.map(\.method)).sorted { $0.displayName < $1.displayName }
        let presentDifficulties = Set(recipes.map(\.difficulty))
        difficulties = [Difficulty.easy, .medium, .advanced].filter(presentDifficulties.contains)
    }
}

public extension GroupedMatchResults {
    /// The Can make view filtered without re-running the engine: tiers and the
    /// order within them are kept.
    func filtered(by filter: RecipeFilter, index: TaxonomyIndex) -> GroupedMatchResults {
        guard !filter.isEmpty else { return self }
        let keep = { (result: RecipeMatchResult) in filter.matches(result.recipe, index: index) }
        return GroupedMatchResults(results: perfect.filter(keep) + almost.filter(keep) + exploring.filter(keep))
    }
}
