import SwiftUI

/// The user's rating, read-only: five stars, filled up to the rating. One
/// accessibility element ("Rated, 4 of 5"). Interactive rating is `StarRatingControl`.
struct RatingStars: View {
    let rating: Int
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .font(font)
                    .foregroundStyle(star <= rating ? DesignTokens.accent : DesignTokens.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue("\(rating) of 5")
    }
}
