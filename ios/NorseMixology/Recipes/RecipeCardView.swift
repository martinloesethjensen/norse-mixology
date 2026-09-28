import Foundation
import SwiftUI
import NorseMixologyCore

/// A single result in the Recipe Browser: name, glass, method/difficulty, and
/// how well the cabinet covers it.
struct RecipeCardView: View {
    let result: RecipeMatchResult
    var isSelected = false
    /// How long to wait before this card's entrance animation starts —
    /// computed by `RecipeResultsList` from the card's tier and position, so
    /// Perfect Match arrives first and each tier staggers in after it.
    var revealDelay: Double = 0

    @Environment(FavouritesViewModel.self) private var favourites
    @Environment(RecipeBrowserViewModel.self) private var browserViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var hasAppeared = false
    @State private var isPulsing = false
    /// Set once, from `reveal()`, based on a snapshot of `hasBeenRevealed`
    /// taken *before* `markRevealed` mutates that same observed state — never
    /// derived live from `browserViewModel` inside `body`, since `reveal()`'s
    /// own mutation would otherwise retrigger this view's body and flip the
    /// badge's `playHeroSweep` back off mid-animation.
    @State private var playHeroSweep = false
    @State private var sweepDelay: Double = 0

    private var recipe: Recipe { result.recipe }
    private var isPerfectMatch: Bool { result.matchType == .exact }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(recipe.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 8)
                if favourites.isFavourited(recipe.id) {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(DesignTokens.accent)
                        .accessibilityLabel("Favourite")
                }
                Image(systemName: recipe.glassType.symbolName)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityLabel("\(recipe.glassType.displayName) glass")
            }

            HStack(spacing: 8) {
                Text(recipe.method.displayName)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                OutlinePillView(text: recipe.difficulty.displayName)
            }

            MatchBadgeView(state: MatchBadgeState(result: result), playHeroSweep: playHeroSweep, sweepDelay: sweepDelay)

            if let firstSubstitution = result.substitutions.first {
                HStack(spacing: 8) {
                    OutlinePillView(
                        text: "\(firstSubstitution.substitute.name) for \(firstSubstitution.required.name)",
                        tint: DesignTokens.matchSubstituted,
                        uppercase: false
                    )
                    if result.substitutions.count > 1 {
                        Text("+\(result.substitutions.count - 1) more")
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.accent : DesignTokens.border, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .scaleEffect(isPulsing ? 1.02 : 1)
        .opacity(reduceMotion || hasAppeared ? 1 : 0)
        .offset(y: reduceMotion || hasAppeared ? 0 : 8)
        .onAppear(perform: reveal)
    }

    private func reveal() {
        let wasAlreadyRevealed = browserViewModel.hasBeenRevealed(result.id, isExactMatch: isPerfectMatch)
        browserViewModel.markRevealed(result.id, isExactMatch: isPerfectMatch)

        // `!hasAppeared` guards against a second onAppear on the SAME still-mounted
        // view instance (e.g. TabView re-firing onAppear when the Recipes tab is
        // revisited) after a cabinet change cleared the shared reveal record —
        // without this, an already-fully-shown card could get a stray pulse with
        // no accompanying sweep, since its own state already sits at the fully
        // revealed end state.
        guard !reduceMotion, !wasAlreadyRevealed, !hasAppeared else {
            hasAppeared = true
            return
        }

        // Only the initial screenful of a reveal "wave" gets the staggered delay —
        // a card revealed later purely by scrolling a long LazyVStack shouldn't sit
        // blank for up to ~0.4s before fading in.
        let elapsedSinceWaveStart = Date().timeIntervalSince(browserViewModel.revealWaveStartedAt)
        let effectiveDelay = elapsedSinceWaveStart < 0.6 ? revealDelay : 0

        if isPerfectMatch {
            playHeroSweep = true
            sweepDelay = effectiveDelay
        }

        withAnimation(.easeOut(duration: 0.3).delay(effectiveDelay)) {
            hasAppeared = true
        }

        guard isPerfectMatch else { return }
        // Not tied to the view's lifecycle — nothing cancels this Task, it
        // just runs the pulse once on its own clock after the sweep finishes.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((effectiveDelay + MatchBadgeView.sweepDuration) * 1000)))
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = true }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = false }
        }
    }
}
