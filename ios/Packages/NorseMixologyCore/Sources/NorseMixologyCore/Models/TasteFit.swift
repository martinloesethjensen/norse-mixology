import Foundation

public enum TasteLean: Equatable, Sendable {
    case toward, away, neutral
}

/// "How does this suit me?" — the quiz answers read against a flavour profile
/// (Tasting Dots design). Every function returns "no opinion" unless the quiz
/// has really been answered, so a skipped quiz never shows a diamond.
public enum TasteFit {
    public static let towardThreshold = 0.67
    public static let awayThreshold = 0.33
    /// How far an ingredient must sit from your answer before the detail says so.
    public static let gapThreshold = 0.35

    /// Which way the user leans on one axis. `.neutral` when the quiz is
    /// unfinished or skipped, or the answer is in the middle.
    public static func lean(of taste: UserTasteProfile, on axis: FlavorAxis) -> TasteLean {
        guard TasteRanking.isActive(taste) else { return .neutral }
        let value = axis.value(in: taste)
        if value >= towardThreshold { return .toward }
        if value <= awayThreshold { return .away }
        return .neutral
    }

    /// Axes the user leans toward, in axis order — the chips that earn a diamond.
    public static func axesLeaningToward(_ taste: UserTasteProfile) -> [FlavorAxis] {
        FlavorAxis.allCases.filter { lean(of: taste, on: $0) == .toward }
    }

    /// The sentence for the ingredient detail, and the axis it is about (nil
    /// when the ingredient is close to the user's taste). Nil with no finished quiz.
    public struct Summary: Equatable, Sendable {
        public let headline: String
        public let axis: FlavorAxis?
    }

    public static func summary(for flavor: FlavorProfile, taste: UserTasteProfile) -> Summary? {
        guard TasteRanking.isActive(taste) else { return nil }

        var biggest: (axis: FlavorAxis, gap: Double)?
        for axis in FlavorAxis.allCases {
            let answer = axis.value(in: taste)
            guard abs(answer - 0.5) > 0.001 else { continue } // no opinion on this axis
            let gap = axis.value(in: flavor) - answer
            if biggest == nil || abs(gap) > abs(biggest!.gap) {
                biggest = (axis, gap)
            }
        }
        guard let biggest else { return nil }
        guard abs(biggest.gap) >= gapThreshold else {
            return Summary(headline: "Close to your taste.", axis: nil)
        }
        return Summary(headline: phrase(biggest.axis, higher: biggest.gap > 0), axis: biggest.axis)
    }

    private static func phrase(_ axis: FlavorAxis, higher: Bool) -> String {
        switch (axis, higher) {
        case (.sweet, true): return "Sweeter than you usually go."
        case (.sweet, false): return "Drier than you usually go."
        case (.bitter, true): return "Bolder and more bitter than you usually go."
        case (.bitter, false): return "Smoother and less bitter than you usually go."
        case (.smoky, true): return "Smokier than you usually go."
        case (.smoky, false): return "Cleaner and less smoky than you usually go."
        case (.citrus, true): return "Brighter and more citrusy than you usually go."
        case (.citrus, false): return "Richer and less citrusy than you usually go."
        case (.herbal, true): return "More herbal than you usually go."
        case (.herbal, false): return "Simpler and less herbal than you usually go."
        }
    }
}
