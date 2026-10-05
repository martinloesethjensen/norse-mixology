import SwiftUI

/// Search/filters hide every recipe.
struct NoMatchingRecipesView: View {
    let onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No recipes match", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Try a different search or remove a filter.")
        } actions: {
            Button("Clear filters", action: onClear)
                .buttonStyle(.dsPrimary)
                .frame(maxWidth: 280)
        }
        .dsScreenBackground()
    }
}
