import SwiftUI
import NorseMixologyCore

/// An ingredient's full flavour profile: a sentence in words, five labelled
/// bars, and — after a finished taste quiz — how it sits against the user's usual.
struct IngredientDetailView: View {
    let title: String
    let subtitle: String
    let profile: FlavorProfile

    @Environment(\.dismiss) private var dismiss
    @State private var taste = TasteProfileStore.load()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .dsText(.display)
                            .foregroundStyle(DesignTokens.textPrimary)
                        if !subtitle.isEmpty {
                            Text(subtitle)
                                .dsText(.body)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(FlavorNotes.headline(for: profile))
                            .dsText(.heading)
                            .foregroundStyle(DesignTokens.textPrimary)
                        if let background = FlavorNotes.background(for: profile) {
                            Text(background)
                                .dsText(.body)
                                .foregroundStyle(DesignTokens.textSecondary)
                        }
                    }

                    // The answer to "does it suit me?" comes before the evidence, so it
                    // is visible without dragging the sheet taller.
                    fitPanel

                    FlavorBarsView(profile: profile, taste: taste)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DesignTokens.surface))
                        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dsScreenBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func gapCaption(_ axis: FlavorAxis?) -> LocalizedStringKey {
        guard let axis else { return "Based on your taste quiz." }
        let name = axis.settingsTitle.lowercased()
        return "The biggest gap is \(name). Based on your taste quiz."
    }

    @ViewBuilder
    private var fitPanel: some View {
        if let fit = TasteFit.summary(for: profile, taste: taste) {
            VStack(alignment: .leading, spacing: 4) {
                Text(fit.headline)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Text(gapCaption(fit.axis))
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DesignTokens.noteStrongFill))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(DesignTokens.noteStrongBorder, lineWidth: 1))
            .accessibilityElement(children: .combine)
        } else {
            Text("Take the taste quiz in Settings to see how this suits you.")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
        }
    }
}
