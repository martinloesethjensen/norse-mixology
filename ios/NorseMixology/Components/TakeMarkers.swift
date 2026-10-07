import SwiftUI
import NorseMixologyCore

/// A quiet "Note" / "N photos" line for recipes the user has added to. Draws
/// nothing for recipes they haven't, so untouched lists look exactly as before.
struct TakeMarkers: View {
    let recipeId: UUID

    @Environment(RecipeTakeViewModel.self) private var take

    var body: some View {
        let hasNote = take.hasNotes.contains(recipeId)
        let photos = take.photoCounts[recipeId] ?? 0
        let photoLabel: LocalizedStringKey = photos == 1 ? "1 photo" : "\(photos) photos"

        if hasNote || photos > 0 {
            HStack(spacing: 10) {
                if hasNote {
                    Label("Note", systemImage: "note.text")
                }
                if photos > 0 {
                    Label(photoLabel, systemImage: "photo")
                }
            }
            .dsText(.body)
            .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
