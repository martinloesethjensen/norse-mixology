import SwiftUI
import SwiftData
import NorseMixologyCore

/// The Settings tab: shows the saved taste profile read-only and offers
/// "Retake Quiz", which presents `TasteOnboardingView` as a sheet.
/// Cancelling the sheet leaves the stored profile untouched; completing it
/// overwrites the profile shown here. The Backup section saves everything the
/// user has made to a `.nmbackup` file and restores from one.
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

                BackupSection()
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

    private var captionText: LocalizedStringKey {
        if !profile.hasCompletedOnboarding { return "You haven't taken the taste quiz yet." }
        return TasteRanking.isActive(profile) ? "Based on your taste quiz answers." : "No preference yet. Retake the quiz to set yours."
    }
}

#Preview {
    if let container = try? ModelContainer(
        for: CabinetItem.self, FavouriteRecipe.self, ShoppingItem.self, RecipeTake.self, RecipePhoto.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        SettingsView()
            .environment(BackupViewModel(container: container, appVersion: "preview"))
    } else {
        Text("Couldn't create the preview data container")
    }
}
