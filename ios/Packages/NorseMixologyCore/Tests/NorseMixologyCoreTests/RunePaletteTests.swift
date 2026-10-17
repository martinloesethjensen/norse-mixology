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

    /// Match colours are also used as body text ("Ready" status lines,
    /// substitution notes, the Substitutions heading), not only as icons.
    func testMatchColoursAsTextContrast() {
        let backgrounds = [("background", RunePalette.background)] + surfaces
        assertContrast(("matchExact", RunePalette.matchExact), on: backgrounds, atLeast: 4.5)
        assertContrast(("matchSubstituted", RunePalette.matchSubstituted), on: backgrounds, atLeast: 4.5)
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

    // MARK: - App sources agree with the palette

    private var appDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // NorseMixologyCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // NorseMixologyCore
            .deletingLastPathComponent() // Packages
            .deletingLastPathComponent() // ios
            .appending(path: "NorseMixology")
    }

    /// Reads an asset-catalog colour set as (dark, light) 0xRRGGBB values.
    private func colorSet(_ name: String) throws -> PaletteColor {
        let url = appDirectory.appending(path: "Assets.xcassets/\(name).colorset/Contents.json")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let entries = try XCTUnwrap(json["colors"] as? [[String: Any]])
        var light: UInt32?
        var dark: UInt32?
        for entry in entries {
            let components = try XCTUnwrap((entry["color"] as? [String: Any])?["components"] as? [String: String])
            func channel(_ key: String) throws -> UInt32 {
                let raw = try XCTUnwrap(components[key])
                if raw.hasPrefix("0x") { return try XCTUnwrap(UInt32(raw.dropFirst(2), radix: 16)) }
                let number = try XCTUnwrap(Double(raw))
                return raw.contains(".") ? UInt32((number * 255).rounded()) : UInt32(number)
            }
            let rgb = try channel("red") << 16 | channel("green") << 8 | channel("blue")
            let appearances = entry["appearances"] as? [[String: String]] ?? []
            if appearances.contains(where: { $0["value"] == "dark" }) {
                dark = rgb
            } else if appearances.isEmpty {
                light = rgb
            }
        }
        return PaletteColor(dark: try XCTUnwrap(dark, "\(name) has no dark entry"),
                            light: try XCTUnwrap(light, "\(name) has no default entry"))
    }

    func testAssetCatalogColoursMatchPalette() throws {
        XCTAssertEqual(try colorSet("AccentColor"), RunePalette.accent)
        // The launch screen hands off to the first screen without a colour jump.
        XCTAssertEqual(try colorSet("LaunchBackground"), RunePalette.background)
    }

    func testNoNeonLimeLeft() throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: appDirectory, includingPropertiesForKeys: nil))
        var offenders: [String] = []
        for case let url as URL in files {
            let path = url.path
            if path.contains("/Resources/") { continue } // catalog JSON: "lime" is the fruit
            guard ["swift", "json"].contains(url.pathExtension),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let lower = text.lowercased()
            if lower.contains("8fe388") || (lower.contains("\"0x8f\"") && lower.contains("\"0xe3\"")) {
                offenders.append(url.lastPathComponent + " (hex)")
            }
            if url.pathExtension == "swift", lower.contains("lime") {
                offenders.append(url.lastPathComponent + " (\"lime\")")
            }
        }
        XCTAssertEqual(offenders, [])
    }

    func testSwapAndAccentHuesAreApartInDark() {
        let distance = abs(WCAG.hueDegrees(RunePalette.accent.dark) - WCAG.hueDegrees(RunePalette.matchSubstituted.dark))
        XCTAssertGreaterThanOrEqual(distance, 10)
    }
}
