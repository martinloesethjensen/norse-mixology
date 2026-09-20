import SwiftUI
import NorseMixologyCore

/// A single result in the Recipe Browser: name, glass, method/difficulty, and
/// how well the cabinet covers it.
struct RecipeCardView: View {
    let result: RecipeMatchResult
    var isSelected = false

    private var recipe: Recipe { result.recipe }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(recipe.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 8)
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

            MatchBadgeView(state: MatchBadgeState(result: result))

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
    }
}
