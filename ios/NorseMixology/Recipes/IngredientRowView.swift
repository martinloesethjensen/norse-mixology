import SwiftUI
import NorseMixologyCore

/// One ingredient line on the recipe detail screen, showing whether the
/// cabinet covers it. Substituted rows expand inline to show the note.
struct IngredientRowView: View {
    let name: String
    let ingredient: RecipeIngredient
    let status: AvailabilityStatus
    let substitute: SubstitutionDetail?
    /// Set only for a missing *required* ingredient: shows a trailing "add to cabinet" button.
    var onAdd: (() -> Void)? = nil

    @State private var isExpanded = false
    @ScaledMetric(relativeTo: .headline) private var iconWidth: CGFloat = 22
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let substitute {
            Button {
                if reduceMotion {
                    isExpanded.toggle()
                } else {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                }
            } label: {
                rowContent(substitute: substitute)
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the substitution note" : "Shows the substitution note")
        } else if let onAdd {
            HStack(alignment: .top, spacing: 4) {
                rowContent(substitute: nil)
                Button(action: onAdd) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(DesignTokens.accent)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Add \(name) to cabinet"))
            }
        } else {
            rowContent(substitute: nil)
        }
    }

    private func rowContent(substitute: SubstitutionDetail?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: status.symbolName)
                    .foregroundStyle(status.color)
                    .frame(width: iconWidth)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .dsText(.heading)
                        .foregroundStyle(status == .unavailable ? DesignTokens.textSecondary : DesignTokens.textPrimary)

                    Text(detailLine)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)

                    if let substitute {
                        Text("Using \(substitute.substitute.name)")
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.matchSubstituted)
                    }
                }

                Spacer(minLength: 8)

                if substitute != nil {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DesignTokens.textSecondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 3)
                }
            }

            if let substitute, isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text(substitute.note)
                    if let ratioHint = substitute.ratioHint {
                        Text(ratioHint)
                    }
                }
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
                .padding(.leading, iconWidth + 12)
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(accessibilityStatus)
    }

    /// "60ml, freshly squeezed · optional"
    private var detailLine: String {
        var parts = [ingredient.amount]
        if let preparation = ingredient.preparation, !preparation.isEmpty {
            parts.append(preparation)
        }
        var line = parts.joined(separator: ", ")
        if ingredient.isOptional { line += " · optional" }
        return line
    }

    private var accessibilityStatus: String {
        switch status {
        case .exact: return "In your cabinet"
        case .substituted: return "Substituted"
        case .unavailable: return "Not in your cabinet"
        }
    }
}
