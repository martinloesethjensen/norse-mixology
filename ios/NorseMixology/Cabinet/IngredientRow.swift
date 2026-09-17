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
                if !style.exampleBrands.isEmpty {
                    Text(style.exampleBrands.prefix(2).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            FlavorProfileIndicatorView(profile: style.flavorProfile)
            if isInCabinet {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .opacity(isInCabinet ? 0.5 : 1.0)
    }
}
