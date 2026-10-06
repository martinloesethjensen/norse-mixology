import Foundation

/// The five flavour axes the app shows — the ones the taste quiz asks about.
/// Declared in the order the old dots used, which stays the fixed order of
/// every bar list so the layout can be learned.
public enum FlavorAxis: CaseIterable, Hashable, Sendable {
    case sweet, bitter, smoky, citrus, herbal

    /// Chip and bar label: "Sweet", "Bitter", …
    public var displayName: String {
        switch self {
        case .sweet: return "Sweet"
        case .bitter: return "Bitter"
        case .smoky: return "Smoky"
        case .citrus: return "Citrus"
        case .herbal: return "Herbal"
        }
    }

    /// Settings row title: "Sweetness", "Bitterness", …
    public var settingsTitle: String {
        switch self {
        case .sweet: return "Sweetness"
        case .bitter: return "Bitterness"
        case .smoky: return "Smokiness"
        case .citrus: return "Citrus"
        case .herbal: return "Herbal"
        }
    }

    /// The quiz answer that sets this axis low (0.15) — the left end of its Settings line.
    public var lowPole: String {
        switch self {
        case .sweet: return "Dry"
        case .bitter: return "Smooth and mellow"
        case .smoky: return "Clean and crisp"
        case .citrus: return "Rich and deep"
        case .herbal: return "Simple and spirit-forward"
        }
    }

    /// The quiz answer that sets this axis high (0.85) — the right end of its Settings line.
    public var highPole: String {
        switch self {
        case .sweet: return "Sweet"
        case .bitter: return "Bitter and bold"
        case .smoky: return "Smoky and peaty"
        case .citrus: return "Bright and citrusy"
        case .herbal: return "Herbal and botanical"
        }
    }

    public func value(in profile: FlavorProfile) -> Double {
        switch self {
        case .sweet: return profile.sweetness
        case .bitter: return profile.bitterness
        case .smoky: return profile.smokiness
        case .citrus: return profile.citrus
        case .herbal: return profile.herbal
        }
    }

    public func value(in profile: UserTasteProfile) -> Double {
        switch self {
        case .sweet: return profile.sweetness
        case .bitter: return profile.bitterness
        case .smoky: return profile.smokiness
        case .citrus: return profile.citrus
        case .herbal: return profile.herbal
        }
    }
}

/// One chip: a flavour that stands out in an ingredient or recipe.
public struct FlavorNote: Equatable, Sendable {
    public let axis: FlavorAxis
    /// 0.67 and up. A strong chip is solid; a mild one (0.5–0.67) is outlined.
    public let isStrong: Bool

    public init(axis: FlavorAxis, isStrong: Bool) {
        self.axis = axis
        self.isStrong = isStrong
    }
}

/// Turns a 0…1 flavour profile into words (Tasting Dots design). Thresholds:
/// a note shows at 0.5 or more; 0.67 and up is strong; 0.34 and up is worth
/// a mention. Level words reuse `FlavorLevel`'s Low/Medium/High cut-offs.
public enum FlavorNotes {
    public static let noteThreshold = 0.5
    public static let strongThreshold = 0.67
    public static let mentionThreshold = 0.34

    /// Up to `limit` notes at 0.5 or more, strongest first; equal scores keep axis order.
    public static func notes(for profile: FlavorProfile, limit: Int = 2) -> [FlavorNote] {
        guard limit > 0 else { return [] }
        let qualifying = FlavorAxis.allCases
            .map { (axis: $0, value: $0.value(in: profile)) }
            .filter { $0.value >= noteThreshold }
        // `sorted` is stable on current Swift, but make the axis-order tie-break explicit.
        let ranked = qualifying.enumerated().sorted { lhs, rhs in
            lhs.element.value != rhs.element.value ? lhs.element.value > rhs.element.value : lhs.offset < rhs.offset
        }
        return ranked.prefix(limit).map { FlavorNote(axis: $0.element.axis, isStrong: $0.element.value >= strongThreshold) }
    }

    /// "None" for a zero score, otherwise Low / Medium / High.
    public static func levelWord(_ value: Double) -> String {
        if value < 0.05 { return "None" }
        return FlavorLevel(value: value).rawValue.capitalized
    }

    /// "Strongly bitter." · "Mildly sweet and herbal." · "Neutral. Little flavour of its own."
    public static func headline(for profile: FlavorProfile) -> String {
        let strong = ranked(profile) { $0 >= strongThreshold }.prefix(2).map(\.axis)
        if !strong.isEmpty {
            return "Strongly \(names(strong))."
        }
        let mild = ranked(profile) { $0 >= noteThreshold }.prefix(2).map(\.axis)
        if !mild.isEmpty {
            return "Mildly \(names(mild))."
        }
        return "Neutral. Little flavour of its own."
    }

    /// "Herbal in the background." — medium notes the headline didn't already name.
    public static func background(for profile: FlavorProfile) -> String? {
        let mentioned = Set(headlineAxes(for: profile))
        let quiet = ranked(profile) { $0 >= mentionThreshold && $0 < strongThreshold }
            .map(\.axis)
            .filter { !mentioned.contains($0) }
            .prefix(2)
        guard !quiet.isEmpty else { return nil }
        let inOrder = FlavorAxis.allCases.filter { quiet.contains($0) }
        let sentence = inOrder.map { $0.displayName.lowercased() }.joined(separator: " and ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst() + " in the background."
    }

    // MARK: - Helpers

    private static func headlineAxes(for profile: FlavorProfile) -> [FlavorAxis] {
        let strong = ranked(profile) { $0 >= strongThreshold }.prefix(2).map(\.axis)
        if !strong.isEmpty { return Array(strong) }
        return Array(ranked(profile) { $0 >= noteThreshold }.prefix(2).map(\.axis))
    }

    /// Axes passing `include`, highest score first, axis order breaking ties.
    private static func ranked(_ profile: FlavorProfile, where include: (Double) -> Bool) -> [(axis: FlavorAxis, value: Double)] {
        var scored: [(axis: FlavorAxis, value: Double)] = []
        for axis in FlavorAxis.allCases {
            let value = axis.value(in: profile)
            if include(value) { scored.append((axis, value)) }
        }
        // Insertion order is axis order, so a stable pass on the score keeps ties in axis order.
        var result: [(axis: FlavorAxis, value: Double)] = []
        for entry in scored {
            let position = result.firstIndex { entry.value > $0.value } ?? result.count
            result.insert(entry, at: position)
        }
        return result
    }

    private static func names(_ axes: [FlavorAxis]) -> String {
        axes.map { $0.displayName.lowercased() }.joined(separator: " and ")
    }
}
