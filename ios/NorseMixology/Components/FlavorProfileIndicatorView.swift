import SwiftUI
import NorseMixologyCore

/// A row of small coloured dots giving an at-a-glance read of an
/// ingredient/recipe's character: Sweetness, Bitterness, Smokiness,
/// Citrus, Herbal. Reused on ingredient rows in Cabinet and Add Ingredient.
struct FlavorProfileIndicatorView: View {
    let profile: FlavorProfile

    private var dimensions: [(label: String, value: Double, color: Color)] {
        [
            ("Sweetness", profile.sweetness, .pink),
            ("Bitterness", profile.bitterness, .orange),
            ("Smokiness", profile.smokiness, .gray),
            ("Citrus", profile.citrus, .yellow),
            ("Herbal", profile.herbal, .green),
        ]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(dimensions, id: \.label) { dimension in
                Circle()
                    .fill(dimension.color.opacity(0.25 + dimension.value * 0.75))
                    .frame(width: 8, height: 8)
                    .accessibilityLabel("\(dimension.label): \(Int(dimension.value * 100))%")
            }
        }
    }
}

#Preview {
    FlavorProfileIndicatorView(
        profile: FlavorProfile(sweetness: 0.2, bitterness: 0.1, smokiness: 0, citrus: 0.4, floral: 0.6, spice: 0.1, herbal: 0.5, fruity: 0.3, oaky: 0, abv: 41.4)
    )
    .padding()
}
