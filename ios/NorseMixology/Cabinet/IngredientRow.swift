import SwiftUI
import NorseMixologyCore

struct IngredientRow: View {
    let style: IngredientStyle
    let familyName: String
    let isInCabinet: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                FlavorNoteChips(profile: style.flavorProfile)
                    .padding(.top, 4)
            }
            Spacer()
            if isInCabinet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.matchExact)
                    .accessibilityHidden(true)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .opacity(isInCabinet ? 0.5 : 1.0)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.65), value: isInCabinet)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(isInCabinet ? "Already in your cabinet" : "")
    }
}
