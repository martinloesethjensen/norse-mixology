import SwiftUI

/// Five 44 pt stars. Tapping a star calls `onSelect(star)`; the view model decides
/// that tapping the current rating clears it. For VoiceOver the stars are one
/// adjustable control ("Your rating, 4 of 5": swipe up/down to change).
struct StarRatingControl: View {
    let rating: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    onSelect(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .font(.title2)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .foregroundStyle(star <= rating ? DesignTokens.accent : DesignTokens.textSecondary)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where rating < 5: onSelect(rating + 1)
            case .decrement where rating > 0: onSelect(rating - 1)
            default: break
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}
