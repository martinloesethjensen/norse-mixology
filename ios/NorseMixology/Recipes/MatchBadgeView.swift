import SwiftUI
import NorseMixologyCore

/// Filled pill communicating how completely the cabinet covers a recipe.
/// Lime = everything on hand, gold = substitutions needed
/// (see Design System → match-status colours).
struct MatchBadgeView: View {
    let state: MatchBadgeState
    /// Plays a one-shot diagonal highlight sweep across the badge — reserved
    /// for a recipe's first appearance as a Perfect Match (see
    /// `RecipeCardView`). Never set for Almost There / Worth Exploring: there
    /// is no numeric score on this badge to "fill," only a hero moment for
    /// the one tier that represents "you can make this right now."
    var playHeroSweep = false
    /// Matches the owning `RecipeCardView`'s `revealDelay`, so the sweep
    /// starts exactly as that card's own fade-in becomes visible instead of
    /// playing (and finishing) while the card is still transparent.
    var sweepDelay: Double = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweepProgress: CGFloat = 0

    var body: some View {
        Text(state.label)
            .dsText(.label)
            .textCase(.uppercase)
            .tracking(0.6)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(DesignTokens.onBadge)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(state.color))
            .overlay(sweepHighlight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state == .exact ? "All ingredients in your cabinet" : state.label)
            .onAppear(perform: startSweepIfNeeded)
            .onChange(of: playHeroSweep) {
                if playHeroSweep {
                    startSweepIfNeeded()
                }
            }
    }

    @ViewBuilder
    private var sweepHighlight: some View {
        if playHeroSweep, !reduceMotion {
            GeometryReader { proxy in
                let width = proxy.size.width
                LinearGradient(
                    colors: [.clear, .white.opacity(0.55), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: width * 0.6)
                .offset(x: -width * 0.6 + sweepProgress * width * 1.6)
            }
            .mask(Capsule())
            .allowsHitTesting(false)
        }
    }

    private func startSweepIfNeeded() {
        guard playHeroSweep, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 0.35).delay(sweepDelay)) {
            sweepProgress = 1
        }
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
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1))
    }
}
