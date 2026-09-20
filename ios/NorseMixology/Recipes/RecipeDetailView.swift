import SwiftUI
import NorseMixologyCore

/// Full recipe: header, ingredients with cabinet availability, substitution
/// notes, and method steps.
///
/// `match` is `nil` for a recipe the current cabinet can't make (reachable from
/// Favourites): ingredients are then simply in the cabinet or not, and there is
/// no substitution callout.
struct RecipeDetailView: View {
    let recipe: Recipe
    let match: RecipeMatchResult?
    let cabinetStyleIds: Set<UUID>

    @Environment(TaxonomyStore.self) private var taxonomyStore
    @Environment(FavouritesViewModel.self) private var favourites
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var heartIsPulsing = false

    init(recipe: Recipe, match: RecipeMatchResult?, cabinetStyleIds: Set<UUID>) {
        self.recipe = recipe
        self.match = match
        self.cabinetStyleIds = cabinetStyleIds
    }

    init(result: RecipeMatchResult, cabinetStyleIds: Set<UUID>) {
        self.init(recipe: result.recipe, match: result, cabinetStyleIds: cabinetStyleIds)
    }

    private var substitutions: [SubstitutionDetail] { match?.substitutions ?? [] }
    private var isFavourite: Bool { favourites.isFavourited(recipe.id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if !recipe.description.isEmpty {
                    Text(recipe.description)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }

                ingredientsSection

                if !substitutions.isEmpty {
                    substitutionCallout
                }

                if !recipe.steps.isEmpty {
                    methodSection
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: toggleFavourite) {
                    Image(systemName: isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavourite ? DesignTokens.accent : DesignTokens.textSecondary)
                        .scaleEffect(heartIsPulsing ? 1.3 : 1)
                }
                .sensoryFeedback(.impact(weight: .medium), trigger: isFavourite)
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
            }
        }
    }

    private func toggleFavourite() {
        favourites.toggle(recipe)
        guard !reduceMotion else { return }

        // Brief scale-up bounce on tap.
        withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { heartIsPulsing = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { heartIsPulsing = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: recipe.glassType.symbolName)
                    .font(.title2)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityLabel("\(recipe.glassType.displayName) glass")
                Text(recipe.name)
                    .dsText(.display)
                    .foregroundStyle(DesignTokens.textPrimary)
            }

            HStack(spacing: 8) {
                OutlinePillView(text: recipe.method.displayName)
                OutlinePillView(text: recipe.difficulty.displayName)
                if let match {
                    MatchBadgeView(state: MatchBadgeState(result: match))
                } else {
                    OutlinePillView(text: "Missing ingredients")
                }
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Ingredients")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(RecipeAvailability.rows(for: recipe, substitutions: substitutions, cabinetStyleIds: cabinetStyleIds)) { row in
                    IngredientRowView(
                        name: taxonomyStore.stylesById[row.ingredient.ingredientStyleId]?.name ?? "Unknown ingredient",
                        ingredient: row.ingredient,
                        status: row.status,
                        substitute: row.substitution
                    )
                }
            }
        }
    }

    // MARK: - Substitutions

    private var substitutionCallout: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Substitutions", systemImage: "arrow.triangle.2.circlepath")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.matchSubstituted)

            ForEach(Array(substitutions.enumerated()), id: \.offset) { _, substitution in
                VStack(alignment: .leading, spacing: 3) {
                    Text("Using \(substitution.substitute.name) instead of \(substitution.required.name)")
                        .dsText(.heading)
                        .foregroundStyle(DesignTokens.textPrimary)
                    Text(substitution.note)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                    if let ratioHint = substitution.ratioHint {
                        Text(ratioHint)
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignTokens.surfaceRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignTokens.matchSubstituted.opacity(0.5), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
    }

    // MARK: - Method

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Method")
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .dsText(.label)
                            .foregroundStyle(DesignTokens.textSecondary)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(DesignTokens.border, lineWidth: 1))
                            .accessibilityHidden(true)
                        Text(step)
                            .dsText(.heading)
                            .fontWeight(.regular)
                            .foregroundStyle(DesignTokens.textPrimary)
                            .accessibilityLabel("Step \(index + 1): \(step)")
                    }
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .dsText(.heading)
            .foregroundStyle(DesignTokens.textPrimary)
            .accessibilityAddTraits(.isHeader)
    }
}
