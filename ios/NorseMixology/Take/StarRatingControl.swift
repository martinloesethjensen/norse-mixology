import SwiftUI
import NorseMixologyCore

/// Five 44 pt stars. Tapping the left half of a star selects a half rating (3.5), the
/// right half a whole one (4); `onSelect` gets the value and the view model decides that
/// tapping the current rating clears it. For VoiceOver the stars are one adjustable
/// control ("Your rating, 4.5 of 5": swipe up/down to change in half steps).
struct StarRatingControl: View {
    let rating: Double
    let onSelect: (Double) -> Void

    private let step = TakeLimits.ratingStep

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                StarGlyph(star: star, rating: rating)
                    .font(.title2)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(width: 44, height: 44)
                    .overlay {
                        HStack(spacing: 0) {
                            half(Double(star) - step)
                            half(Double(star))
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating.ratingText) of 5")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment where rating < TakeLimits.ratingRange.upperBound: onSelect(rating + step)
            case .decrement where rating > TakeLimits.ratingRange.lowerBound: onSelect(rating - step)
            default: break
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }

    private func half(_ value: Double) -> some View {
        Button {
            onSelect(value)
        } label: {
            Color.clear.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }
}
