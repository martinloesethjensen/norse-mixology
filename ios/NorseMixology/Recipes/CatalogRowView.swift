import SwiftUI
import NorseMixologyCore

/// One recipe in All recipes: name, glass, and what it still needs.
struct CatalogRowView: View {
    let entry: CatalogEntry
    var isSelected = false

    @Environment(FavouritesViewModel.self) private var favourites
    @Environment(RecipeBrowserViewModel.self) private var browser

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.recipe.glassType.symbolName)
                .foregroundStyle(DesignTokens.textSecondary)
                .accessibilityLabel(Text("\(entry.recipe.glassType.displayName) glass"))
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.recipe.name)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                statusText
                    .dsText(.body)
                    .foregroundStyle(statusColor)
                FlavorNoteChips(profile: browser.noteProfile(for: entry.recipe), taste: browser.tasteProfile)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            if favourites.isFavourited(entry.recipe.id) {
                Image(systemName: "heart.fill")
                    .foregroundStyle(DesignTokens.accent)
                    .accessibilityLabel("Favourite")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? DesignTokens.surfaceRaised : DesignTokens.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? DesignTokens.accent : DesignTokens.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var statusText: Text {
        if let match = entry.match {
            switch MatchBadgeState(result: match) {
            case .exact: return Text("Ready")
            case .substituted(let count): return count == 1 ? Text("Ready · 1 sub") : Text("Ready · \(count) subs")
            }
        }
        switch entry.missing.count {
        case 0: return Text("Unavailable")
        case 1: return Text("Needs \(entry.missing[0].name)")
        default: return Text("Missing \(entry.missing.count)")
        }
    }

    private var statusColor: Color {
        guard let match = entry.match else { return DesignTokens.textSecondary }
        return match.matchType == .exact ? DesignTokens.matchExact : DesignTokens.matchSubstituted
    }
}
