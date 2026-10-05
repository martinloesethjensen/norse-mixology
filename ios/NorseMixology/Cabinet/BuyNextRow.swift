import SwiftUI
import NorseMixologyCore

/// One "buy next" bottle: what it unlocks, and a button to put it on the list.
struct BuyNextRow: View {
    let suggestion: BuyNextSuggestion
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.style.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                subtitle
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(action: onAdd) {
                Image(systemName: "cart.badge.plus")
                    .font(.title3)
                    .foregroundStyle(DesignTokens.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add \(suggestion.style.name) to shopping list"))
        }
    }

    /// "+3 ready now · Last Word, Alaska, +1" or "Gets 24 recipes closer".
    private var subtitle: Text {
        guard suggestion.readyNow > 0 else {
            return suggestion.movesCloser == 1
                ? Text("Gets 1 recipe closer")
                : Text("Gets \(suggestion.movesCloser) recipes closer")
        }
        let shown = suggestion.readyNowRecipeNames.prefix(2).joined(separator: ", ")
        let more = suggestion.readyNowRecipeNames.count - 2
        return more > 0
            ? Text("+\(suggestion.readyNow) ready now · \(shown), +\(more)")
            : Text("+\(suggestion.readyNow) ready now · \(shown)")
    }
}
