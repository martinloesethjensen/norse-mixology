import SwiftUI
import NorseMixologyCore

/// All recipes: Ready / Missing 1 / Missing 2 / Missing 3+. Deliberately no
/// entrance or hero animation — this list is for scanning 150+ recipes.
struct CatalogList: View {
    let grouped: GroupedAvailability
    let interaction: RecipeResultsList.Interaction
    let onRefresh: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                section("Ready", subtitle: "You can make these now", tier: .ready)
                section("Missing 1", subtitle: "One bottle away", tier: .missing1)
                section("Missing 2", subtitle: "Two bottles away", tier: .missing2)
                section("Missing 3+", subtitle: "Worth a shopping trip", tier: .missing3Plus)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .dsScreenBackground()
        .refreshable { onRefresh() }
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, subtitle: LocalizedStringKey, tier: AvailabilityTier) -> some View {
        let entries = grouped.entries(in: tier)
        if !entries.isEmpty {
            Section {
                ForEach(entries) { row(for: $0) }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    (Text(title) + Text(verbatim: " (\(entries.count))"))
                        .dsText(.heading)
                        .foregroundStyle(DesignTokens.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Text(subtitle)
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
    private func row(for entry: CatalogEntry) -> some View {
        switch interaction {
        case .push:
            NavigationLink(value: entry.id) { CatalogRowView(entry: entry) }
                .buttonStyle(.plain)
        case .select(let selectedID, let onSelect):
            Button { onSelect(entry.id) } label: {
                CatalogRowView(entry: entry, isSelected: entry.id == selectedID)
            }
            .buttonStyle(.plain)
        }
    }
}
