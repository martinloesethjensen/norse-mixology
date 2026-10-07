import SwiftUI
import NorseMixologyCore

/// The notes box. Saved 0.6 s after typing stops, when the screen goes away, and
/// when the app leaves the foreground — there is no Save button to forget.
struct TakeNotesEditor: View {
    let recipe: Recipe

    @Environment(RecipeTakeViewModel.self) private var take
    @Environment(\.scenePhase) private var scenePhase
    @State private var text = ""
    @State private var saveTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    private let counterThreshold = 1_800

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("What would you change? What did you serve it with?")
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                TextEditor(text: $text)
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textPrimary)
                    .scrollContentBackground(.hidden)
                    .focused($isFocused)
                    .frame(minHeight: 96)
                    .accessibilityLabel("Notes")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DesignTokens.surface))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))

            if text.count >= counterThreshold {
                Text("\(text.count) of \(TakeLimits.maxNotesLength)")
                    .dsText(.body)
                    .foregroundStyle(DesignTokens.textSecondary)
                    .accessibilityLabel("\(text.count) of \(TakeLimits.maxNotesLength) characters")
            }
        }
        .onAppear { text = take.notes(for: recipe.id) }
        .onChange(of: text) { _, newValue in
            if newValue.count > TakeLimits.maxNotesLength {
                text = String(newValue.prefix(TakeLimits.maxNotesLength))
                return
            }
            scheduleSave()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { flush() }
        }
        .onDisappear { flush() }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            flush()
        }
    }

    /// Saves now, unless nothing changed (loading the stored text also fires `onChange`).
    private func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard text != take.notes(for: recipe.id) else { return }
        take.setNotes(text, for: recipe)
    }
}
