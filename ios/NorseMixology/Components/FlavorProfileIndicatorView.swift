import SwiftUI
import NorseMixologyCore

/// A row of small dots giving an at-a-glance read of an ingredient's
/// character — Sweetness, Bitterness, Smokiness, Citrus, Herbal, in that
/// order. The lime fill's strength shows how pronounced each is. Read aloud
/// as one element: "Sweetness: high, Bitterness: low, …".
struct FlavorProfileIndicatorView: View {
    let profile: FlavorProfile

    private var values: [Double] {
        [profile.sweetness, profile.bitterness, profile.smokiness, profile.citrus, profile.herbal]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                Circle()
                    .fill(DesignTokens.accent.opacity(0.15 + value * 0.85))
                    .overlay(Circle().strokeBorder(DesignTokens.border, lineWidth: 0.5))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flavour profile")
        .accessibilityValue(profile.accessibilitySummary)
    }
}

#Preview {
    FlavorProfileIndicatorView(
        profile: FlavorProfile(sweetness: 0.2, bitterness: 0.1, smokiness: 0, citrus: 0.4, floral: 0.6, spice: 0.1, herbal: 0.5, fruity: 0.3, oaky: 0, abv: 41.4)
    )
    .padding()
}
