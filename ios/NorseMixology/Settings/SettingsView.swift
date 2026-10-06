import SwiftUI
import NorseMixologyCore

/// The Settings tab: shows the saved taste profile read-only and offers
/// "Retake Quiz", which presents `TasteOnboardingView` as a sheet.
/// Cancelling the sheet leaves the stored profile untouched; completing it
/// overwrites the profile shown here. Also holds the pantry staples, which
/// recipes treat as always in stock (Pantry Staples spec §3).
struct SettingsView: View {
    @State private var profile = TasteProfileStore.load()
    @State private var isRetakingQuiz = false
    @State private var pantry = PantryStore.load()

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

                Section {
                    ForEach(PantryStaple.allCases) { staple in
                        Toggle(staple.title, isOn: pantryBinding(for: staple))
                            .tint(DesignTokens.accent)
                            .listRowBackground(DesignTokens.surface)
                    }
                } header: {
                    Text("Pantry")
                } footer: {
                    Text("Recipes treat these as always in stock. They stay out of your cabinet and are never suggested to buy.")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .dsScreenBackground()
            .navigationTitle("Settings")
        }
        .onAppear {
            profile = TasteProfileStore.load()
            pantry = PantryStore.load()
        }
        .sheet(isPresented: $isRetakingQuiz) {
            TasteOnboardingView(isPresentedAsRetake: true) { updated in
                profile = updated
                isRetakingQuiz = false
            }
        }
    }

    /// Saves on every change; the Recipes and Shopping list screens re-match when they next appear.
    private func pantryBinding(for staple: PantryStaple) -> Binding<Bool> {
        Binding(
            get: { pantry.contains(staple) },
            set: { isOn in
                if isOn { pantry.insert(staple) } else { pantry.remove(staple) }
                PantryStore.save(pantry)
            }
        )
    }

    private var captionText: LocalizedStringKey {
        if !profile.hasCompletedOnboarding { return "You haven't taken the taste quiz yet." }
        return TasteRanking.isActive(profile) ? "Based on your taste quiz answers." : "No preference yet. Retake the quiz to set yours."
    }
}

private extension PantryStaple {
    var title: LocalizedStringKey {
        switch self {
        case .sugar: return "Sugar"
        case .honey: return "Honey"
        case .eggs: return "Eggs"
        case .sodaWater: return "Soda water"
        case .lemonsAndLimes: return "Lemons and limes"
        case .oranges: return "Oranges"
        case .salt: return "Salt"
        }
    }
}

#Preview {
    SettingsView()
}
