import SwiftUI
import NorseMixologyCore

/// The grouped result cards (Perfect Match / Almost There / Worth Exploring).
///
/// Takes plain values rather than builder closures so SwiftUI re-renders the
/// cards whenever the match results change.
struct RecipeResultsList: View {
    enum Interaction {
        /// Compact width: each card is a `NavigationLink(value:)` pushed onto an enclosing `NavigationStack`.
        case push
        /// Regular width: tapping a card selects it for the detail pane.
        case select(selectedID: UUID?, onSelect: (UUID) -> Void)
    }

    let grouped: GroupedMatchResults
    let interaction: Interaction
    let onRefresh: () -> Void

    var body: some View {
        if grouped.isEmpty {
            ContentUnavailableView(
                "No Matching Recipes",
                systemImage: "wineglass",
                description: Text("Your cabinet didn't match any recipes. Try adding some base spirits like gin, rum, or vodka.")
            )
            .dsScreenBackground()
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    section("🍹 Perfect Match", subtitle: "You have everything", matches: grouped.perfect)
                    section("🔄 Almost There", subtitle: "Missing 1 ingredient", matches: grouped.almost)
                    section("🔍 Worth Exploring", subtitle: "Needs a few subs", matches: grouped.exploring)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .dsScreenBackground()
            .refreshable { onRefresh() }
        }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringResource, subtitle: LocalizedStringResource, matches: [RecipeMatchResult]) -> some View {
        if !matches.isEmpty {
            Section {
                ForEach(matches) { result in
                    card(for: result)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(String(localized: title)) (\(matches.count))")
                        .dsText(.heading)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(String(localized: subtitle))
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .padding(.bottom, 4)
            }
        }
    }

    @ViewBuilder
    private func card(for result: RecipeMatchResult) -> some View {
        switch interaction {
        case .push:
            NavigationLink(value: result.id) {
                RecipeCardView(result: result)
            }
            .buttonStyle(.plain)
        case .select(let selectedID, let onSelect):
            Button {
                onSelect(result.id)
            } label: {
                RecipeCardView(result: result, isSelected: result.id == selectedID)
            }
            .buttonStyle(.plain)
        }
    }
}
