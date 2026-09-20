import SwiftUI
import NorseMixologyCore

struct IngredientRow: View {
    let style: IngredientStyle
    let familyName: String
    let isInCabinet: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                if !style.exampleBrands.isEmpty {
                    Text(style.exampleBrands.prefix(2).joined(separator: ", "))
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            Spacer()
            FlavorProfileIndicatorView(profile: style.flavorProfile)
            if isInCabinet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.matchExact)
                    .accessibilityHidden(true)
            }
        }
        .opacity(isInCabinet ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isInCabinet ? "Already in your cabinet" : "")
    }
}
