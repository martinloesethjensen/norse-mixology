import SwiftUI
import NorseMixologyCore

/// Filled pill communicating how completely the cabinet covers a recipe.
/// Lime = everything on hand, gold = substitutions needed
/// (see Design System → match-status colours).
struct MatchBadgeView: View {
    let state: MatchBadgeState

    var body: some View {
        Text(state.label)
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(DesignTokens.onBadge)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(state.color))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state == .exact ? "All ingredients in your cabinet" : state.label)
    }
}

/// Small outlined pill for secondary facts (difficulty, substituted ingredient).
struct OutlinePillView: View {
    let text: String
    var tint: Color = DesignTokens.textSecondary
    /// Short labels (difficulty, method) read as tags in caps; longer ones
    /// (ingredient names) stay in their natural case so they fit.
    var uppercase = true

    var body: some View {
        Text(text)
            .dsText(.label)
            .textCase(uppercase ? .uppercase : nil)
            .tracking(uppercase ? 0.6 : 0.2)
            .lineLimit(1)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }
}
