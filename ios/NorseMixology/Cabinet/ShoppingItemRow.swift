import SwiftUI
import NorseMixologyCore

/// One shopping-list item. The leading circle marks it bought (moves it to the
/// cabinet). A ghost item — its style left the catalog — can't be ticked.
struct ShoppingItemRow: View {
    let entry: ShoppingEntry
    let familyName: String
    let onBought: () -> Void

    private var isGhost: Bool { entry.style == nil }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onBought) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(isGhost ? DesignTokens.matchUnavailable : DesignTokens.accent)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isGhost)
            .accessibilityLabel(Text("Bought \(entry.item.styleName), move to cabinet"))

            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.item.styleName)
                    .dsText(.heading)
                    .foregroundStyle(isGhost ? DesignTokens.textSecondary : DesignTokens.textPrimary)
                if isGhost {
                    Text("No longer in the catalog")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                } else {
                    Text(verbatim: familyName)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }
}
