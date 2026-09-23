import SwiftUI
import NorseMixologyCore

/// The Settings tab: shows the saved taste profile read-only and offers
/// "Retake Quiz", which presents `TasteOnboardingView` as a sheet.
/// Cancelling the sheet leaves the stored profile untouched; completing it
/// overwrites the profile shown here.
struct SettingsView: View {
    @State private var profile = TasteProfileStore.load()
    @State private var isRetakingQuiz = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Your Taste") {
                    VStack(alignment: .leading, spacing: 8) {
                        FlavorProfileIndicatorView(profile: displayFlavorProfile)
                        Text(profile.hasCompletedOnboarding ? "Based on your taste quiz answers." : "You haven't taken the taste quiz yet.")
                            .dsText(.body)
                            .foregroundStyle(DesignTokens.textSecondary)
                    }
                    .listRowBackground(DesignTokens.surface)
                }

                Section {
                    Button("Retake Quiz") { isRetakingQuiz = true }
                        .listRowBackground(DesignTokens.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .navigationTitle("Settings")
        }
        .onAppear { profile = TasteProfileStore.load() }
        .sheet(isPresented: $isRetakingQuiz) {
            TasteOnboardingView(isPresentedAsRetake: true) { updated in
                profile = updated
                isRetakingQuiz = false
            }
        }
    }

    /// `FlavorProfileIndicatorView` only ever reads sweetness/bitterness/
    /// smokiness/citrus/herbal (see its `values` and `FlavorProfile.
    /// accessibilitySummary`), so the un-quizzed fields below are filler
    /// that is never displayed — this is display-only reuse, not a
    /// comparison, so it doesn't violate the "never default and compare
    /// un-quizzed axes" rule.
    private var displayFlavorProfile: FlavorProfile {
        FlavorProfile(
            sweetness: profile.sweetness, bitterness: profile.bitterness, smokiness: profile.smokiness,
            citrus: profile.citrus, floral: 0, spice: 0, herbal: profile.herbal, fruity: 0, oaky: 0, abv: 0
        )
    }
}

#Preview {
    SettingsView()
}
