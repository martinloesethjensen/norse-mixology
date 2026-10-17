import Foundation

/// One design-system colour as 0xRRGGBB, resolved per system appearance.
public struct PaletteColor: Equatable, Sendable {
    public let dark: UInt32
    public let light: UInt32

    public init(dark: UInt32, light: UInt32) {
        self.dark = dark
        self.light = light
    }

    /// A colour that is the same in both appearances.
    public init(_ both: UInt32) {
        self.init(dark: both, light: both)
    }
}

/// The "Rune" design system's colour values — oxblood, brass and bone (see
/// NORSE_MIXOLOGY_BUILD.md → Design System). Kept free of UIKit so the
/// contrast floor is unit-tested here; the app's `DesignTokens` maps these
/// to SwiftUI colours, and nothing else defines a colour.
public enum RunePalette {
    public static let background = PaletteColor(dark: 0x2A1215, light: 0xF6EEE1)
    public static let surface = PaletteColor(dark: 0x3B1A1E, light: 0xFFFBF4)
    public static let surfaceRaised = PaletteColor(dark: 0x4A2328, light: 0xEFE4D3)
    public static let border = PaletteColor(dark: 0x5A2E33, light: 0xE2D4BE)
    public static let textPrimary = PaletteColor(dark: 0xF0E4D0, light: 0x2A1215)
    // Light value darkened from the spec's #7A6658, which was 4.32:1 on surfaceRaised.
    public static let textSecondary = PaletteColor(dark: 0xB9A99A, light: 0x705C4F)
    /// Brass in dark, oxblood in light.
    public static let accent = PaletteColor(dark: 0xD2AE6A, light: 0x4A1D22)
    /// Text on accent fills (primary buttons).
    public static let onAccent = PaletteColor(dark: 0x3A2A0C, light: 0xF0E4D0)

    // Match / availability: green = can make, copper = swap, grey = missing.
    // Light value darkened from the spec's #3F7A3C: it is also body text, and was 4.11:1 on surfaceRaised.
    public static let matchExact = PaletteColor(dark: 0x7DB37A, light: 0x37703A)
    public static let matchSubstituted = PaletteColor(dark: 0xE5803A, light: 0xA04E12)
    // Dark value lightened from the spec's #7E6A62, which was 2.64:1 on surfaceRaised.
    public static let matchUnavailable = PaletteColor(dark: 0x8C7870, light: 0x8A7B6E)
    public static let matchExactBadgeFill = PaletteColor(dark: 0x7DB37A, light: 0xDCEBD8)
    public static let matchExactBadgeText = PaletteColor(dark: 0x14290F, light: 0x2D5A2A)
    public static let matchSubstitutedBadgeFill = PaletteColor(dark: 0xE5803A, light: 0xF6DCC6)
    public static let matchSubstitutedBadgeText = PaletteColor(dark: 0x3A1A06, light: 0x7A3A0C)

    // Flavour notes (Tasting Dots) follow the accent, so green keeps meaning "can make".
    public static let noteStrongText = PaletteColor(dark: 0xD2AE6A, light: 0x4A1D22)
    public static let noteStrongFill = PaletteColor(dark: 0x4A2328, light: 0xF1E2CF)
    public static let noteStrongBorder = PaletteColor(dark: 0x8C6E3A, light: 0x8E3A3F)
    public static let noteMildBorder = PaletteColor(dark: 0x8C7870, light: 0x9C8A7C)
    public static let noteBar = PaletteColor(dark: 0xD2AE6A, light: 0x4A1D22)

    // App icon and launch artwork (ios/design/*.svg use the same values).
    public static let iconOxblood: UInt32 = 0x4A1D22
    public static let iconBrass: UInt32 = 0xD2AE6A
    public static let iconLiquid: UInt32 = 0x8E3A3F
}

/// WCAG 2.x colour maths for 0xRRGGBB values.
public enum WCAG {
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// HSL hue in 0..<360.
    public static func hueDegrees(_ c: UInt32) -> Double {
        let (r, g, b) = channels(c)
        let maxC = max(r, g, b)
        let delta = maxC - min(r, g, b)
        guard delta > 0 else { return 0 }
        let hue: Double
        if maxC == r {
            hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxC == g {
            hue = 60 * ((b - r) / delta + 2)
        } else {
            hue = 60 * ((r - g) / delta + 4)
        }
        return hue < 0 ? hue + 360 : hue
    }

    private static func channels(_ c: UInt32) -> (Double, Double, Double) {
        (Double((c >> 16) & 0xFF) / 255, Double((c >> 8) & 0xFF) / 255, Double(c & 0xFF) / 255)
    }

    private static func relativeLuminance(_ c: UInt32) -> Double {
        func linear(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let (r, g, b) = channels(c)
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
}
