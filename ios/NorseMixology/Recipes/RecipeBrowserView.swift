import SwiftUI
import NorseMixologyCore

/// Stub results screen reached from Cabinet's "Find Recipes" — the full
/// grouped browser UI (Perfect Match / Almost There / Worth Exploring)
/// lands in Phase 4.
struct RecipeBrowserView: View {
    let results: [RecipeMatchResult]

    var body: some View {
        Group {
            if results.isEmpty {
                ContentUnavailableView(
                    "No Recipes Found",
                    systemImage: "wineglass",
                    description: Text("Try adding a few more ingredients to your cabinet.")
                )
            } else {
                List(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(result.recipe.name)
                                .font(.headline)
                            Spacer()
                            Text(result.matchType == .exact ? "Exact" : "\(Int(result.matchScore * 100))%")
                                .font(.caption)
                                .foregroundStyle(result.matchType == .exact ? .green : .orange)
                        }
                        if let firstSub = result.substitutions.first {
                            Text(firstSub.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("\(results.count) Recipe\(results.count == 1 ? "" : "s")")
        .navigationBarTitleDisplayMode(.inline)
    }
}
