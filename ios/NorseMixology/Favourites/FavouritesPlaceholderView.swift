import SwiftUI

/// Stub tab — the real Favourites screen lands in Phase 5.
struct FavouritesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Favourites",
                systemImage: "heart",
                description: Text("Coming soon — save recipes to see them here.")
            )
            .navigationTitle("Favourites")
        }
    }
}
