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
                        TasteLinesView(profile: profile)
                        Text(captionText)
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

    private var captionText: String {
        if !profile.hasCompletedOnboarding { return "You haven't taken the taste quiz yet." }
        return TasteRanking.isActive(profile) ? "Based on your taste quiz answers." : "No preference yet. Retake the quiz to set yours."
    }
}

#Preview {
    SettingsView()
}
