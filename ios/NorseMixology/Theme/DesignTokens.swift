import SwiftUI
import UIKit
import NorseMixologyCore

/// "Rune" tokens — oxblood, brass and bone — for both system appearances
/// (see NORSE_MIXOLOGY_BUILD.md → Design System). The values live in
/// `RunePalette` (core), where their contrast is unit-tested.
///
/// Every screen takes its colours and text styles from here — nothing else in
/// the app hard-codes a colour or a font size.
enum DesignTokens {
    static let background = Color.adaptive(RunePalette.background)
    static let surface = Color.adaptive(RunePalette.surface)
    static let surfaceRaised = Color.adaptive(RunePalette.surfaceRaised)
    static let border = Color.adaptive(RunePalette.border)
    /// Brass in dark, oxblood in light.
    static let accent = Color.adaptive(RunePalette.accent)
    /// Text on accent fills (the primary button).
    static let onAccent = Color.adaptive(RunePalette.onAccent)
    static let textPrimary = Color.adaptive(RunePalette.textPrimary)
    static let textSecondary = Color.adaptive(RunePalette.textSecondary)

    static let matchExact = Color.adaptive(RunePalette.matchExact)
    static let matchSubstituted = Color.adaptive(RunePalette.matchSubstituted)
    static let matchUnavailable = Color.adaptive(RunePalette.matchUnavailable)

    // Match badges: solid in dark, tinted pill with dark text in light.
    static let matchExactBadgeFill = Color.adaptive(RunePalette.matchExactBadgeFill)
    static let matchExactBadgeText = Color.adaptive(RunePalette.matchExactBadgeText)
    static let matchSubstitutedBadgeFill = Color.adaptive(RunePalette.matchSubstitutedBadgeFill)
    static let matchSubstitutedBadgeText = Color.adaptive(RunePalette.matchSubstitutedBadgeText)

    // Flavour notes (Tasting Dots): strong = tinted fill, mild = outline only.
    static let noteStrongText = Color.adaptive(RunePalette.noteStrongText)
    static let noteStrongFill = Color.adaptive(RunePalette.noteStrongFill)
    static let noteStrongBorder = Color.adaptive(RunePalette.noteStrongBorder)
    static let noteMildBorder = Color.adaptive(RunePalette.noteMildBorder)
    static let noteBar = Color.adaptive(RunePalette.noteBar)
}

extension Color {
    /// A palette colour that resolves to its dark or light value following
    /// the system appearance.
    static func adaptive(_ color: PaletteColor) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? color.dark : color.light)
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

    var badgeFill: Color {
        switch self {
        case .exact: return DesignTokens.matchExactBadgeFill
        case .substituted: return DesignTokens.matchSubstitutedBadgeFill
        }
    }

    var badgeText: Color {
        switch self {
        case .exact: return DesignTokens.matchExactBadgeText
        case .substituted: return DesignTokens.matchSubstitutedBadgeText
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

/// The primary call-to-action: filled accent (brass / oxblood), at least 44pt tall.
struct DSPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .dsText(.heading)
            .foregroundStyle(DesignTokens.onAccent)
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
