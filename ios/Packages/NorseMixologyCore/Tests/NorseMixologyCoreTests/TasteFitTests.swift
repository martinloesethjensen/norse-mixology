import XCTest
@testable import NorseMixologyCore

/// Tasting Dots design: "you" is a diamond. A recipe chip gets one when the
/// quiz says you lean that way; the ingredient detail says how far an
/// ingredient is from your usual. Nothing is shown without a finished quiz.
final class TasteFitTests: XCTestCase {
    private func flavor(sweet: Double = 0, bitter: Double = 0, smoky: Double = 0, citrus: Double = 0, herbal: Double = 0) -> FlavorProfile {
        FlavorProfile(sweetness: sweet, bitterness: bitter, smokiness: smoky, citrus: citrus,
                      floral: 0, spice: 0, herbal: herbal, fruity: 0, oaky: 0, abv: 20)
    }

    /// The design's example user: likes sweet, smooth, bright, clean and herbal.
    private let sweetSmoothBright = UserTasteProfile(
        sweetness: 0.85, bitterness: 0.15, citrus: 0.85, smokiness: 0.15, herbal: 0.85, hasCompletedOnboarding: true)

    // MARK: - Lean

    func testLeanFollowsTheQuizAnswers() {
        XCTAssertEqual(TasteFit.lean(of: sweetSmoothBright, on: .sweet), .toward)
        XCTAssertEqual(TasteFit.lean(of: sweetSmoothBright, on: .bitter), .away)
        XCTAssertEqual(TasteFit.lean(of: sweetSmoothBright, on: .smoky), .away)
        XCTAssertEqual(TasteFit.lean(of: sweetSmoothBright, on: .citrus), .toward)
        XCTAssertEqual(TasteFit.lean(of: sweetSmoothBright, on: .herbal), .toward)
    }

    func testMiddleValuesHaveNoLean() {
        let middling = UserTasteProfile(sweetness: 0.6, bitterness: 0.4, citrus: 0.85, smokiness: 0.15, herbal: 0.5,
                                        hasCompletedOnboarding: true)
        XCTAssertEqual(TasteFit.lean(of: middling, on: .sweet), .neutral)
        XCTAssertEqual(TasteFit.lean(of: middling, on: .bitter), .neutral)
        XCTAssertEqual(TasteFit.lean(of: middling, on: .herbal), .neutral)
    }

    func testNoLeanWithoutAFinishedQuiz() {
        let unfinished = UserTasteProfile(sweetness: 0.85, bitterness: 0.15, citrus: 0.85, smokiness: 0.15, herbal: 0.85,
                                          hasCompletedOnboarding: false)
        for axis in FlavorAxis.allCases {
            XCTAssertEqual(TasteFit.lean(of: unfinished, on: axis), .neutral)
            XCTAssertEqual(TasteFit.lean(of: .neutral, on: axis), .neutral)
        }
        // The quiz's Skip path saves a completed profile with every axis at 0.5: also no preference.
        let skipped = UserTasteProfile(hasCompletedOnboarding: true)
        for axis in FlavorAxis.allCases { XCTAssertEqual(TasteFit.lean(of: skipped, on: axis), .neutral) }
    }

    func testAxesYouLeanTowardOnlyListsMatches() {
        XCTAssertEqual(TasteFit.axesLeaningToward(sweetSmoothBright), [.sweet, .citrus, .herbal])
        XCTAssertEqual(TasteFit.axesLeaningToward(.neutral), [])
    }

    // MARK: - Fit sentence

    func testBiggestGapPicksTheLargestDifferenceAndSaysWhichWay() {
        // Bitter Aperitif: bitter 0.9 against 0.15 is the biggest gap.
        let aperitif = flavor(sweet: 0.3, bitter: 0.9, smoky: 0, citrus: 0.3, herbal: 0.4)
        let fit = TasteFit.summary(for: aperitif, taste: sweetSmoothBright)
        XCTAssertEqual(fit?.headline, "Bolder and more bitter than you usually go.")
        XCTAssertEqual(fit?.axis, .bitter)
    }

    func testEachAxisHasAPhraseInBothDirections() {
        let expectedHigher: [FlavorAxis: String] = [
            .sweet: "Sweeter than you usually go.",
            .bitter: "Bolder and more bitter than you usually go.",
            .smoky: "Smokier than you usually go.",
            .citrus: "Brighter and more citrusy than you usually go.",
            .herbal: "More herbal than you usually go.",
        ]
        let expectedLower: [FlavorAxis: String] = [
            .sweet: "Drier than you usually go.",
            .bitter: "Smoother and less bitter than you usually go.",
            .smoky: "Cleaner and less smoky than you usually go.",
            .citrus: "Richer and less citrusy than you usually go.",
            .herbal: "Simpler and less herbal than you usually go.",
        ]
        let allMiddle = UserTasteProfile(sweetness: 0.15, bitterness: 0.85, citrus: 0.15, smokiness: 0.85, herbal: 0.15,
                                         hasCompletedOnboarding: true)
        for axis in FlavorAxis.allCases {
            // Only this axis is far from the user's answer.
            var values: [FlavorAxis: Double] = [.sweet: 0.15, .bitter: 0.85, .smoky: 0.85, .citrus: 0.15, .herbal: 0.15]
            values[axis] = 1.0 - values[axis]!
            let probe = flavor(sweet: values[.sweet]!, bitter: values[.bitter]!, smoky: values[.smoky]!,
                               citrus: values[.citrus]!, herbal: values[.herbal]!)
            let fit = TasteFit.summary(for: probe, taste: allMiddle)
            let wantsHigher = axis.value(in: probe) > axis.value(in: allMiddle)
            XCTAssertEqual(fit?.headline, wantsHigher ? expectedHigher[axis] : expectedLower[axis], "\(axis)")
            XCTAssertEqual(fit?.axis, axis)
        }
    }

    func testSmallGapsReadCloseToYourTaste() {
        let close = flavor(sweet: 0.8, bitter: 0.2, smoky: 0.1, citrus: 0.9, herbal: 0.8)
        let fit = TasteFit.summary(for: close, taste: sweetSmoothBright)
        XCTAssertEqual(fit?.headline, "Close to your taste.")
        XCTAssertNil(fit?.axis)
    }

    func testTiedGapsResolveByAxisOrder() {
        let user = UserTasteProfile(sweetness: 0.85, bitterness: 0.85, citrus: 0.85, smokiness: 0.85, herbal: 0.85,
                                    hasCompletedOnboarding: true)
        let fit = TasteFit.summary(for: flavor(), taste: user)
        XCTAssertEqual(fit?.axis, .sweet)
        XCTAssertEqual(fit?.headline, "Drier than you usually go.")
    }

    func testNoSummaryWithoutAFinishedQuiz() {
        XCTAssertNil(TasteFit.summary(for: flavor(bitter: 0.9), taste: .neutral))
        XCTAssertNil(TasteFit.summary(for: flavor(bitter: 0.9), taste: UserTasteProfile(hasCompletedOnboarding: true)))
        XCTAssertNil(TasteFit.summary(for: flavor(bitter: 0.9), taste: UserTasteProfile(sweetness: 0.85, hasCompletedOnboarding: false)))
    }

    func testAxesWithNoOpinionAreIgnoredWhenFindingTheGap() {
        // Only sweetness has an opinion; a huge bitter score must not count.
        let partial = UserTasteProfile(sweetness: 0.85, bitterness: 0.5, citrus: 0.5, smokiness: 0.5, herbal: 0.5,
                                       hasCompletedOnboarding: true)
        let fit = TasteFit.summary(for: flavor(sweet: 0.1, bitter: 1.0), taste: partial)
        XCTAssertEqual(fit?.axis, .sweet)
        XCTAssertEqual(fit?.headline, "Drier than you usually go.")
    }
}
