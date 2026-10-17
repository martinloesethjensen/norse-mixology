import XCTest
@testable import NorseMixologyCore

/// "Rune" design system: pins the contrast floor and the colour rules the
/// design depends on (see docs/superpowers/specs/2026-10-17-rune-identity-design.md §5).
final class RunePaletteTests: XCTestCase {
    private enum Mode: String, CaseIterable { case dark, light }

    private func value(_ color: PaletteColor, _ mode: Mode) -> UInt32 {
        mode == .dark ? color.dark : color.light
    }

    private func assertContrast(
        _ foreground: (String, PaletteColor),
        on backgrounds: [(String, PaletteColor)],
        atLeast minimum: Double,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        for mode in Mode.allCases {
            for background in backgrounds {
                let ratio = WCAG.contrastRatio(value(foreground.1, mode), value(background.1, mode))
                XCTAssertGreaterThanOrEqual(
                    ratio, minimum,
                    "\(foreground.0) on \(background.0) (\(mode.rawValue)) is \(String(format: "%.2f", ratio)):1",
                    file: file, line: line
                )
            }
        }
    }

    private let surfaces: [(String, PaletteColor)] = [
        ("surface", RunePalette.surface),
        ("surfaceRaised", RunePalette.surfaceRaised),
    ]

    func testContrastRatioMatchesWCAGReference() {
        XCTAssertEqual(WCAG.contrastRatio(0x000000, 0xFFFFFF), 21, accuracy: 0.01)
        XCTAssertEqual(WCAG.contrastRatio(0xFFFFFF, 0x000000), 21, accuracy: 0.01)
        XCTAssertEqual(WCAG.contrastRatio(0x777777, 0xFFFFFF), 4.48, accuracy: 0.01)
    }

    func testHueDegrees() {
        XCTAssertEqual(WCAG.hueDegrees(0xFF0000), 0, accuracy: 0.01)
        XCTAssertEqual(WCAG.hueDegrees(0x00FF00), 120, accuracy: 0.01)
        XCTAssertEqual(WCAG.hueDegrees(0x0000FF), 240, accuracy: 0.01)
    }

    func testTextContrast() {
        let backgrounds = [("background", RunePalette.background)] + surfaces
        assertContrast(("textPrimary", RunePalette.textPrimary), on: backgrounds, atLeast: 4.5)
        assertContrast(("textSecondary", RunePalette.textSecondary), on: backgrounds, atLeast: 4.5)
        assertContrast(("onAccent", RunePalette.onAccent), on: [("accent", RunePalette.accent)], atLeast: 4.5)
        assertContrast(("noteStrongText", RunePalette.noteStrongText), on: [("noteStrongFill", RunePalette.noteStrongFill)], atLeast: 4.5)
    }

    func testBadgeTextContrast() {
        assertContrast(("matchExactBadgeText", RunePalette.matchExactBadgeText),
                       on: [("matchExactBadgeFill", RunePalette.matchExactBadgeFill)], atLeast: 4.5)
        assertContrast(("matchSubstitutedBadgeText", RunePalette.matchSubstitutedBadgeText),
                       on: [("matchSubstitutedBadgeFill", RunePalette.matchSubstitutedBadgeFill)], atLeast: 4.5)
    }

    func testStatusIconContrast() {
        assertContrast(("accent", RunePalette.accent), on: surfaces, atLeast: 3)
        assertContrast(("matchExact", RunePalette.matchExact), on: surfaces, atLeast: 3)
        assertContrast(("matchSubstituted", RunePalette.matchSubstituted), on: surfaces, atLeast: 3)
        assertContrast(("matchUnavailable", RunePalette.matchUnavailable), on: surfaces, atLeast: 3)
        assertContrast(("noteBar", RunePalette.noteBar), on: surfaces, atLeast: 3)
    }

    func testSwapAndAccentHuesAreApartInDark() {
        let distance = abs(WCAG.hueDegrees(RunePalette.accent.dark) - WCAG.hueDegrees(RunePalette.matchSubstituted.dark))
        XCTAssertGreaterThanOrEqual(distance, 10)
    }
}
