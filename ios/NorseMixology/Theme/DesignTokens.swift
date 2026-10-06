import SwiftUI
import UIKit
import NorseMixologyCore

/// "Modern Neon Bar" tokens from the vault's Design System note, mapped for
/// both system appearances (see NORSE_MIXOLOGY_BUILD.md → Design System).
///
/// Every screen takes its colours and text styles from here — nothing else in
/// the app hard-codes a colour or a font size.
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

    // Flavour notes (Tasting Dots): strong = tinted fill, mild = outline only.
    static let noteStrongText = Color.adaptive(dark: 0x8FE388, light: 0x1F6B2A)
    static let noteStrongFill = Color.adaptive(dark: 0x1B2A21, light: 0xE3F5E1)
    static let noteStrongBorder = Color.adaptive(dark: 0x2F5B3A, light: 0x8CCB8F)
    static let noteMildBorder = Color.adaptive(dark: 0x5B6472, light: 0x7A8493)
    static let noteBar = Color.adaptive(dark: 0x8FE388, light: 0x3FA34D)

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

// MARK: - Shared screen styling

extension View {
    /// The Design System Background token behind a screen's content.
    func dsScreenBackground() -> some View {
        background(DesignTokens.background)
    }

    /// For `List` / `Form`: hides the system grouped background so the
    /// Background token shows through.
    func dsListBackground() -> some View {
        scrollContentBackground(.hidden).background(DesignTokens.background)
    }

    /// Briefly shows `text` as a banner above the bottom edge each time
    /// `trigger` changes (increment it to show), and announces it to VoiceOver.
    func transientNotice(_ text: String, trigger: Int) -> some View {
        modifier(TransientNoticeModifier(text: text, trigger: trigger))
    }
}

private struct TransientNoticeModifier: ViewModifier {
    let text: String
    let trigger: Int
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom) {
                if isVisible {
                    Text(text)
                        .dsText(.heading)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(DesignTokens.surfaceRaised))
                        .overlay(Capsule().strokeBorder(DesignTokens.border, lineWidth: 1))
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            // Each new trigger cancels the previous task, restarting the timer.
            .task(id: trigger) {
                guard trigger > 0 else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isVisible = true }
                AccessibilityNotification.Announcement(text).post()
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) { isVisible = false }
            }
    }
}

/// The primary call-to-action: filled lime with dark text, at least 44pt tall.
struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsText(.heading)
            .foregroundStyle(DesignTokens.onBadge)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.accent.opacity(configuration.isPressed ? 0.8 : 1))
            )
    }
}

extension ButtonStyle where Self == DSPrimaryButtonStyle {
    static var dsPrimary: DSPrimaryButtonStyle { DSPrimaryButtonStyle() }
}
