import SwiftUI
import UIKit
import NorseMixologyCore

/// "Modern Neon Bar" tokens from the vault's Design System note, mapped for
/// both system appearances (see NORSE_MIXOLOGY_BUILD.md → Design System).
///
/// Phase 4 uses these for the recipe cards, badges and detail screen. Wiring
/// them app-wide (backgrounds, tab bar, Cabinet screens) is Phase 6.
enum DesignTokens {
    static let background = Color.adaptive(dark: 0x0D0F14, light: 0xF7F8FA)
    static let surface = Color.adaptive(dark: 0x161920, light: 0xFFFFFF)
    static let surfaceRaised = Color.adaptive(dark: 0x1F232D, light: 0xEFF1F4)
    static let border = Color.adaptive(dark: 0x262B36, light: 0xDDE1E7)
    static let accent = Color(hex: 0x8FE388)
    static let textPrimary = Color.adaptive(dark: 0xEEF1F5, light: 0x14171C)
    static let textSecondary = Color.adaptive(dark: 0x9AA1AF, light: 0x5B6472)

    static let matchExact = Color(hex: 0x8FE388)
    static let matchSubstituted = Color(hex: 0xF0B93D)
    static let matchUnavailable = Color.adaptive(dark: 0x4A5160, light: 0xA6AEBA)

    /// Text on the filled lime/gold badges — dark in both modes for contrast.
    static let onBadge = Color(hex: 0x0D0F14)
}

extension Color {
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// A colour that resolves to `dark` or `light` following the system appearance.
    static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - Typography

/// The Design System's four text roles. Sizes/weights match the spec; they
/// scale with Dynamic Type via `@ScaledMetric`.
enum DSTextStyle {
    case display   // 26 · 800 — recipe titles
    case heading   // 16 · 600 — section headings, card names
    case body      // 13 · 400 — secondary body copy
    case label     // 10 · 700 — badges (callers add uppercase + tracking)

    fileprivate var baseSize: CGFloat {
        switch self {
        case .display: return 26
        case .heading: return 16
        case .body: return 13
        case .label: return 10
        }
    }

    fileprivate var weight: Font.Weight {
        switch self {
        case .display: return .heavy
        case .heading: return .semibold
        case .body: return .regular
        case .label: return .bold
        }
    }

    fileprivate var relativeTo: Font.TextStyle {
        switch self {
        case .display: return .title
        case .heading: return .headline
        case .body: return .footnote
        case .label: return .caption2
        }
    }
}

private struct DSTextModifier: ViewModifier {
    let style: DSTextStyle
    @ScaledMetric private var size: CGFloat

    init(style: DSTextStyle) {
        self.style = style
        _size = ScaledMetric(wrappedValue: style.baseSize, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: style.weight))
    }
}

extension View {
    func dsText(_ style: DSTextStyle) -> some View {
        modifier(DSTextModifier(style: style))
    }
}

// MARK: - Match / availability colours

extension MatchBadgeState {
    var color: Color {
        switch self {
        case .exact: return DesignTokens.matchExact
        case .substituted: return DesignTokens.matchSubstituted
        }
    }
}

extension AvailabilityStatus {
    var color: Color {
        switch self {
        case .exact: return DesignTokens.matchExact
        case .substituted: return DesignTokens.matchSubstituted
        case .unavailable: return DesignTokens.matchUnavailable
        }
    }

    var symbolName: String {
        switch self {
        case .exact: return "checkmark.circle.fill"
        case .substituted: return "arrow.triangle.2.circlepath.circle.fill"
        case .unavailable: return "xmark.circle.fill"
        }
    }
}
