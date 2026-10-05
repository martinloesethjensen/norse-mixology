import SwiftUI
import NorseMixologyCore

extension RecipeFilter.Criterion {
    /// Chip / filter-row text. Tags are catalog slugs ("spirit-forward").
    func label(familyNamesById: [UUID: String]) -> String {
        switch self {
        case .tag(let tag): return tag.replacingOccurrences(of: "-", with: " ").capitalized
        case .strength(let strength): return strength.displayName
        case .baseFamily(let id): return familyNamesById[id] ?? String(localized: "Unknown spirit")
        case .glass(let glass): return glass.displayName
        case .method(let method): return method.displayName
        case .difficulty(let difficulty): return difficulty.displayName
        }
    }
}

/// Top of the Recipes tab: Can make | All recipes, then one removable chip per active filter.
struct BrowseHeader: View {
    @Environment(RecipeBrowserViewModel.self) private var viewModel

    var body: some View {
        @Bindable var viewModel = viewModel
        VStack(alignment: .leading, spacing: 10) {
            Picker("Show", selection: $viewModel.browseState.mode) {
                Text("Can make").tag(RecipeBrowseState.Mode.canMake)
                Text("All recipes").tag(RecipeBrowseState.Mode.all)
            }
            .pickerStyle(.segmented)

            if !viewModel.browseState.filter.criteria.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.browseState.filter.criteria, id: \.self) { criterion in
                        chip(criterion)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(DesignTokens.background)
    }

    private func chip(_ criterion: RecipeFilter.Criterion) -> some View {
        let label = criterion.label(familyNamesById: viewModel.familyNamesById)
        return Button {
            viewModel.browseState.filter.remove(criterion)
        } label: {
            HStack(spacing: 4) {
                Text(label)
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .dsText(.body)
            .foregroundStyle(DesignTokens.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Capsule().fill(DesignTokens.surfaceRaised))
            .overlay(Capsule().strokeBorder(DesignTokens.border, lineWidth: 1))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Remove filter \(label)"))
    }
}
