import SwiftUI
import NorseMixologyCore

/// Full recipe: header, ingredients with cabinet availability, substitution
/// notes, and method steps.
struct RecipeDetailView: View {
    let result: RecipeMatchResult
    let cabinetStyleIds: Set<UUID>

    @Environment(TaxonomyStore.self) private var taxonomyStore
    /// Visual stub — persistence is wired in Phase 5.
    @State private var isFavourite = false

    private var recipe: Recipe { result.recipe }

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

                if !result.substitutions.isEmpty {
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
                Button {
                    isFavourite.toggle()
                } label: {
                    Image(systemName: isFavourite ? "heart.fill" : "heart")
                        .foregroundStyle(isFavourite ? DesignTokens.accent : DesignTokens.textSecondary)
                }
                .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
            }
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
                MatchBadgeView(state: MatchBadgeState(result: result))
            }
        }
    }

    // MARK: - Ingredients

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading("Ingredients")
            VStack(alignment: .leading, spacing: 16) {
                ForEach(RecipeAvailability.rows(for: result, cabinetStyleIds: cabinetStyleIds)) { row in
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

            ForEach(Array(result.substitutions.enumerated()), id: \.offset) { _, substitution in
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
