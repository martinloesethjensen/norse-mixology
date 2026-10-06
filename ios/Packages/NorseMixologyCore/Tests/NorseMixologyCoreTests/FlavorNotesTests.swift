import XCTest
@testable import NorseMixologyCore

/// Tasting Dots design: the five unlabelled dots become named notes (chips in
/// lists, labelled bars in the detail). These tests pin the rules that design
/// states: a note shows at 0.5 or more, strongest first, two at most; 0.67 and
/// up is strong; nothing over 0.5 reads Neutral.
final class FlavorNotesTests: XCTestCase {
    private func profile(
        sweet: Double = 0, bitter: Double = 0, smoky: Double = 0, citrus: Double = 0, herbal: Double = 0
    ) -> FlavorProfile {
        FlavorProfile(sweetness: sweet, bitterness: bitter, smokiness: smoky, citrus: citrus,
                      floral: 0, spice: 0, herbal: herbal, fruity: 0, oaky: 0, abv: 20)
    }

    // Real catalog scores (sweet, bitter, smoky, citrus, herbal).
    private var greenChartreuse: FlavorProfile { profile(sweet: 0.4, bitter: 0.3, smoky: 0, citrus: 0.1, herbal: 0.9) }
    private var bitterAperitif: FlavorProfile { profile(sweet: 0.3, bitter: 0.9, smoky: 0, citrus: 0.3, herbal: 0.4) }
    private var rossoVermouth: FlavorProfile { profile(sweet: 0.6, bitter: 0.3, smoky: 0, citrus: 0.1, herbal: 0.5) }
    private var prosecco: FlavorProfile { profile(sweet: 0.3, bitter: 0, smoky: 0, citrus: 0.2, herbal: 0) }
    private var limeJuice: FlavorProfile { profile(sweet: 0.1, bitter: 0.1, smoky: 0, citrus: 0.9, herbal: 0) }

    // MARK: - Axes

    func testAxesAreInTheOrderTheDotsUsed() {
        XCTAssertEqual(FlavorAxis.allCases, [.sweet, .bitter, .smoky, .citrus, .herbal])
        XCTAssertEqual(FlavorAxis.allCases.map(\.displayName), ["Sweet", "Bitter", "Smoky", "Citrus", "Herbal"])
    }

    func testAxisReadsItsScoreFromBothProfileKinds() {
        let flavor = profile(sweet: 0.1, bitter: 0.2, smoky: 0.3, citrus: 0.4, herbal: 0.5)
        XCTAssertEqual(FlavorAxis.allCases.map { $0.value(in: flavor) }, [0.1, 0.2, 0.3, 0.4, 0.5])
        let taste = UserTasteProfile(sweetness: 0.15, bitterness: 0.25, citrus: 0.35, smokiness: 0.45, herbal: 0.55,
                                     hasCompletedOnboarding: true)
        XCTAssertEqual(FlavorAxis.allCases.map { $0.value(in: taste) }, [0.15, 0.25, 0.45, 0.35, 0.55])
    }

    func testEveryAxisHasQuizPoles() {
        XCTAssertEqual(FlavorAxis.sweet.lowPole, "Dry")
        XCTAssertEqual(FlavorAxis.sweet.highPole, "Sweet")
        XCTAssertEqual(FlavorAxis.bitter.lowPole, "Smooth and mellow")
        XCTAssertEqual(FlavorAxis.bitter.highPole, "Bitter and bold")
        XCTAssertEqual(FlavorAxis.smoky.lowPole, "Clean and crisp")
        XCTAssertEqual(FlavorAxis.smoky.highPole, "Smoky and peaty")
        XCTAssertEqual(FlavorAxis.citrus.lowPole, "Rich and deep")
        XCTAssertEqual(FlavorAxis.citrus.highPole, "Bright and citrusy")
        XCTAssertEqual(FlavorAxis.herbal.lowPole, "Simple and spirit-forward")
        XCTAssertEqual(FlavorAxis.herbal.highPole, "Herbal and botanical")
        XCTAssertEqual(FlavorAxis.allCases.map(\.settingsTitle), ["Sweetness", "Bitterness", "Smokiness", "Citrus", "Herbal"])
    }

    // MARK: - Notes (list chips)

    func testNotesShowAtHalfOrMoreStrongestFirstTwoAtMost() {
        XCTAssertEqual(FlavorNotes.notes(for: greenChartreuse), [FlavorNote(axis: .herbal, isStrong: true)])
        XCTAssertEqual(FlavorNotes.notes(for: bitterAperitif), [FlavorNote(axis: .bitter, isStrong: true)])
        XCTAssertEqual(FlavorNotes.notes(for: limeJuice), [FlavorNote(axis: .citrus, isStrong: true)])
        XCTAssertEqual(FlavorNotes.notes(for: rossoVermouth), [
            FlavorNote(axis: .sweet, isStrong: false), FlavorNote(axis: .herbal, isStrong: false),
        ])
    }

    func testNothingOverHalfIsNeutral() {
        XCTAssertTrue(FlavorNotes.notes(for: prosecco).isEmpty)
        XCTAssertTrue(FlavorNotes.notes(for: profile()).isEmpty)
    }

    func testThresholdsAreInclusiveAtHalfAndAtStrong() {
        let notes = FlavorNotes.notes(for: profile(sweet: 0.5, bitter: 0.49, smoky: 0.67, citrus: 0.66))
        XCTAssertEqual(notes, [FlavorNote(axis: .smoky, isStrong: true), FlavorNote(axis: .citrus, isStrong: false)],
                       "limit 2 keeps the strongest; 0.5 sweet ranks below both and is cut")
        XCTAssertEqual(FlavorNotes.notes(for: profile(sweet: 0.5)), [FlavorNote(axis: .sweet, isStrong: false)])
        XCTAssertTrue(FlavorNotes.notes(for: profile(sweet: 0.49)).isEmpty)
    }

    func testMoreThanTwoQualifyingNotesKeepTheStrongestTwoWithAxisOrderBreakingTies() {
        let notes = FlavorNotes.notes(for: profile(sweet: 0.8, bitter: 0.8, smoky: 0.8, citrus: 0.9, herbal: 0.6))
        XCTAssertEqual(notes.map(\.axis), [.citrus, .sweet])
        XCTAssertEqual(FlavorNotes.notes(for: profile(sweet: 0.8, bitter: 0.8, smoky: 0.8), limit: 3).map(\.axis),
                       [.sweet, .bitter, .smoky])
        XCTAssertTrue(FlavorNotes.notes(for: profile(sweet: 0.8), limit: 0).isEmpty)
    }

    // MARK: - Level words (detail bars)

    func testLevelWordsFollowTheScreenReaderLevelsPlusNone() {
        XCTAssertEqual(FlavorNotes.levelWord(0), "None")
        XCTAssertEqual(FlavorNotes.levelWord(0.04), "None")
        XCTAssertEqual(FlavorNotes.levelWord(0.1), "Low")
        XCTAssertEqual(FlavorNotes.levelWord(0.33), "Low")
        XCTAssertEqual(FlavorNotes.levelWord(0.34), "Medium")
        XCTAssertEqual(FlavorNotes.levelWord(0.66), "Medium")
        XCTAssertEqual(FlavorNotes.levelWord(0.67), "High")
        XCTAssertEqual(FlavorNotes.levelWord(1), "High")
    }

    // MARK: - Detail sentences

    func testHeadlineNamesStrongNotes() {
        XCTAssertEqual(FlavorNotes.headline(for: bitterAperitif), "Strongly bitter.")
        XCTAssertEqual(FlavorNotes.headline(for: greenChartreuse), "Strongly herbal.")
        XCTAssertEqual(FlavorNotes.headline(for: profile(sweet: 0.8, herbal: 0.7)), "Strongly sweet and herbal.")
    }

    func testHeadlineForMildOnlyAndNeutralIngredients() {
        XCTAssertEqual(FlavorNotes.headline(for: rossoVermouth), "Mildly sweet and herbal.")
        XCTAssertEqual(FlavorNotes.headline(for: profile(citrus: 0.55)), "Mildly citrus.")
        XCTAssertEqual(FlavorNotes.headline(for: prosecco), "Neutral. Little flavour of its own.")
    }

    func testBackgroundNamesTheQuieterMediumNotesNotAlreadyMentioned() {
        XCTAssertEqual(FlavorNotes.background(for: bitterAperitif), "Herbal in the background.")
        XCTAssertEqual(FlavorNotes.background(for: greenChartreuse), "Sweet in the background.")
        XCTAssertEqual(FlavorNotes.background(for: profile(sweet: 0.4, bitter: 0.9, herbal: 0.45)),
                       "Sweet and herbal in the background.")
    }

    func testBackgroundIsAbsentWhenThereIsNothingLeftToSay() {
        XCTAssertNil(FlavorNotes.background(for: rossoVermouth), "both medium notes are already in the headline")
        XCTAssertNil(FlavorNotes.background(for: prosecco))
        XCTAssertNil(FlavorNotes.background(for: limeJuice))
    }
}
