import SwiftUI
import NorseMixologyCore

/// "My take" on a recipe: rating, notes and photos. Shown on every recipe screen.
struct MyTakeSection: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take

    var body: some View {
        let rating = take.rating(for: recipe.id)

        VStack(alignment: .leading, spacing: 16) {
            Text("My take")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                StarRatingControl(rating: rating) { take.setRating($0, for: recipe) }
                Text(rating == 0 ? "Not rated" : "\(rating) of 5")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityHidden(true)
            }

            TakeNotesEditor(recipe: recipe)
            TakePhotoStrip(recipe: recipe)
        }
        .alert(
            "Couldn't save your changes",
            isPresented: Binding(get: { take.lastError != nil }, set: { if !$0 { take.clearError() } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your device couldn't save this change right now. It will be saved automatically when it can — check that your device has free space.")
        }
    }
}
