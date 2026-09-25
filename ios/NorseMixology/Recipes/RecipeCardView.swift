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

    private var recipe: Recipe { result.recipe }
    private var isPerfectMatch: Bool { result.matchType == .exact }
    private var isFirstReveal: Bool { !browserViewModel.hasBeenRevealed(result.id) }

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

            MatchBadgeView(state: MatchBadgeState(result: result), playHeroSweep: isPerfectMatch && isFirstReveal)

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
        let wasAlreadyRevealed = browserViewModel.hasBeenRevealed(result.id)
        browserViewModel.markRevealed(result.id)

        guard !reduceMotion, !wasAlreadyRevealed else {
            hasAppeared = true
            return
        }

        withAnimation(.easeOut(duration: 0.3).delay(revealDelay)) {
            hasAppeared = true
        }

        guard isPerfectMatch else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int((revealDelay + 0.35) * 1000)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = true }
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.2)) { isPulsing = false }
        }
    }
}
