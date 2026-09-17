import SwiftUI

/// Stub tab — the real Recipe Browser lands in Phase 4.
struct RecipesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Recipes",
                systemImage: "wineglass",
                description: Text("Coming soon — the recipe browser lands in a later phase.")
            )
            .navigationTitle("Recipes")
        }
    }
}
