import SwiftUI
import NorseMixologyCore

/// The full profile: five named bars in a fixed order, each with its level in
/// words. With a finished quiz, a "you" diamond sits on each axis where the
/// user has an opinion, so "more bitter than I usually go" is visible at a glance.
struct FlavorBarsView: View {
    let profile: FlavorProfile
    var taste: UserTasteProfile? = nil

    @ScaledMetric(relativeTo: .footnote) private var labelWidth: CGFloat = 58
    @ScaledMetric(relativeTo: .footnote) private var wordWidth: CGFloat = 64

    private var activeTaste: UserTasteProfile? {
        guard let taste, TasteRanking.isActive(taste) else { return nil }
        return taste
    }

    private func youValue(on axis: FlavorAxis) -> Double? {
        guard let activeTaste else { return nil }
        let value = axis.value(in: activeTaste)
        return abs(value - 0.5) > 0.001 ? value : nil // no opinion on this axis: no diamond
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(FlavorAxis.allCases, id: \.self) { axis in
                row(axis)
            }
            if FlavorAxis.allCases.contains(where: { youValue(on: $0) != nil }) {
                legend
            }
        }
    }

    private func row(_ axis: FlavorAxis) -> some View {
        let value = axis.value(in: profile)
        let isStrong = value >= FlavorNotes.strongThreshold
        let you = youValue(on: axis)
        let word = FlavorNotes.levelWord(value)

        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(axis.displayName)
                    .dsText(.body)
                    .fontWeight(isStrong ? .semibold : .regular)
                    .foregroundStyle(isStrong ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: labelWidth, alignment: .leading)
                track(value: value, you: you)
                Text(word)
                    .dsText(.body)
                    .fontWeight(isStrong ? .semibold : .regular)
                    .foregroundStyle(isStrong ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                    .frame(width: wordWidth, alignment: .trailing)
            }
            // Large text: name and level on one line, the bar under them.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(axis.displayName)
                    Spacer()
                    Text(word)
                }
                .dsText(.body)
                .fontWeight(isStrong ? .semibold : .regular)
                .foregroundStyle(isStrong ? DesignTokens.textPrimary : DesignTokens.textSecondary)
                track(value: value, you: you)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axis.displayName)
        .accessibilityValue(spokenValue(word: word, you: you))
    }

    private func spokenValue(word: String, you: Double?) -> LocalizedStringKey {
        guard let you else { return LocalizedStringKey(word) }
        let yourWord = FlavorNotes.levelWord(you).lowercased()
        return "\(word). You: \(yourWord)"
    }

    private func track(value: Double, you: Double?) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(DesignTokens.border).frame(height: 8)
                Capsule()
                    .fill(DesignTokens.noteBar)
                    .frame(width: max(0, min(1, value)) * width, height: 8)
                if let you {
                    YouMarker(size: 8)
                        .position(x: max(0, min(1, you)) * width, y: geometry.size.height / 2)
                }
            }
        }
        .frame(height: 16) // room for the diamond above and below the 8 pt rail
        .frame(minWidth: 60)
    }

    private var legend: some View {
        // Side by side when it fits; stacked at large text so no word is ever split.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) { legendThisIngredient; legendYou }
            VStack(alignment: .leading, spacing: 8) { legendThisIngredient; legendYou }
        }
        .dsText(.body)
        .foregroundStyle(DesignTokens.textSecondary)
        .padding(.top, 4)
        .accessibilityHidden(true)
    }

    private var legendThisIngredient: some View {
        HStack(spacing: 8) {
            Capsule().fill(DesignTokens.noteBar).frame(width: 22, height: 8)
            Text("This ingredient").fixedSize(horizontal: true, vertical: false)
        }
    }

    private var legendYou: some View {
        HStack(spacing: 8) {
            YouMarker(size: 8)
            Text("You, from your quiz").fixedSize(horizontal: true, vertical: false)
        }
    }
}
