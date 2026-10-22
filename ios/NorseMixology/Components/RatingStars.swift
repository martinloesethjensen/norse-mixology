import SwiftUI

extension Double {
    /// "4" for whole ratings, "4.5" for half stars.
    var ratingText: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// One star at position `star` (1…5) of a rating: empty, half or full. The three
/// symbols differ slightly in width, so the glyph is laid out against the widest one;
/// changing a rating never moves its neighbours.
struct StarGlyph: View {
    let star: Int
    let rating: Double

    private var isFull: Bool { rating >= Double(star) }
    private var isHalf: Bool { !isFull && rating >= Double(star) - 0.5 }

    private var symbol: String {
        if isFull { return "star.fill" }
        return isHalf ? "star.leadinghalf.filled" : "star"
    }

    var body: some View {
        Image(systemName: "star.fill")
            .hidden()
            .overlay {
                Image(systemName: symbol)
                    .foregroundStyle(isFull || isHalf ? DesignTokens.accent : DesignTokens.textSecondary)
            }
    }
}

/// The user's rating, read-only: five stars, filled up to the rating in half-star steps. One
/// accessibility element (label "Your rating", value "4.5 of 5"). Interactive rating is `StarRatingControl`.
struct RatingStars: View {
    let rating: Double
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                StarGlyph(star: star, rating: rating)
                    .font(font)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue("\(rating.ratingText) of 5")
    }
}
