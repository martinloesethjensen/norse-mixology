import SwiftUI
import NorseMixologyCore

/// The animated 5-question "this-or-that" onboarding quiz. Used both as the
/// full-screen first-run flow (`isPresentedAsRetake: false`, no Cancel
/// button — there is nothing to cancel back to on a fresh install) and as a
/// sheet from Settings' "Retake Quiz" (`isPresentedAsRetake: true`, adds a
/// Cancel button). Swiping the sheet away mid-quiz also leaves the stored
/// profile untouched, since nothing is saved until Skip or the final answer.
struct TasteOnboardingView: View {
    var isPresentedAsRetake: Bool = false
    var onComplete: (UserTasteProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var profile = UserTasteProfile()
    @State private var currentIndex = 0
    @State private var showCelebration = false

    private let questions = TasteQuizQuestion.all

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topTrailing) {
                DesignTokens.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    if !showCelebration {
                        progressHeader
                    }
                    Spacer()
                    if showCelebration {
                        celebration
                    } else {
                        ThisOrThatCard(question: questions[currentIndex], onChoose: answer)
                            .id(questions[currentIndex].id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                    }
                    Spacer()
                }
                .padding(24)

                if !showCelebration {
                    Button("Skip") { skip() }
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(16)
                        .accessibilityHint("Skips the taste quiz and uses a neutral profile")
                }
            }
            .toolbar {
                if isPresentedAsRetake {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(currentIndex + 1) of \(questions.count)")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
            ProgressView(value: Double(currentIndex), total: Double(questions.count))
                .tint(DesignTokens.accent)
        }
        .accessibilityElement(children: .combine)
    }

    /// Built so the two pieces animate independently via SwiftUI's insertion
    /// transitions (driven by the `withAnimation` spring in `answer()` when
    /// `showCelebration` flips to true) rather than a shared property
    /// binding — this is also the localized spot to swap in a real Lottie
    /// animation later without restructuring the rest of the flow.
    private var celebration: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(DesignTokens.accent)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
            Text("You're all set!")
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You're all set!")
        .onTapGesture { finish() }
        .task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            finish()
        }
    }

    private func answer(_ questionId: Int, _ choice: ThisOrThatCard.Choice) {
        guard questionId == questions[currentIndex].id else { return }
        profile[keyPath: questions[currentIndex].axis] = choice == .left ? 0.85 : 0.15
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if currentIndex < questions.count - 1 {
                currentIndex += 1
            } else {
                profile.hasCompletedOnboarding = true
                showCelebration = true
            }
        }
    }

    private func skip() {
        let skippedProfile = UserTasteProfile(hasCompletedOnboarding: true)
        TasteProfileStore.save(skippedProfile)
        onComplete(skippedProfile)
    }

    private func finish() {
        TasteProfileStore.save(profile)
        onComplete(profile)
    }
}

#Preview {
    TasteOnboardingView { _ in }
}
