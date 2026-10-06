import SwiftUI
import NorseMixologyCore

/// What stands out about an ingredient or recipe, in words: up to two chips,
/// strongest first. Solid is strong, outlined is mild, and nothing over 0.5
/// reads "Neutral". With `taste` (a finished quiz), a chip for a flavour the
/// user leans toward gets the "you" diamond.
struct FlavorNoteChips: View {
    let profile: FlavorProfile
    var taste: UserTasteProfile? = nil

    var body: some View {
        let notes = FlavorNotes.notes(for: profile)
        let leaning = taste.map(TasteFit.axesLeaningToward) ?? []

        if notes.isEmpty {
            Text("Neutral")
                .dsText(.body)
                .foregroundStyle(DesignTokens.textSecondary)
        } else {
            FlowLayout(spacing: 8) {
                ForEach(notes, id: \.axis) { note in
                    chip(note, matchesYou: leaning.contains(note.axis))
                }
            }
        }
    }

    /// Whole phrases, so each can be translated as a unit.
    private func spokenStrength(_ note: FlavorNote, matchesYou: Bool) -> LocalizedStringKey {
        switch (note.isStrong, matchesYou) {
        case (true, true): return "Strong, matches your taste"
        case (true, false): return "Strong"
        case (false, true): return "Mild, matches your taste"
        case (false, false): return "Mild"
        }
    }

    private func chip(_ note: FlavorNote, matchesYou: Bool) -> some View {
        HStack(spacing: 6) {
            if matchesYou { YouMarker(size: 6) }
            Text(note.axis.displayName)
                .dsText(.body)
                .fontWeight(.semibold)
        }
        .foregroundStyle(note.isStrong ? DesignTokens.noteStrongText : DesignTokens.textPrimary)
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .frame(minHeight: 26)
        .background(Capsule().fill(note.isStrong ? DesignTokens.noteStrongFill : Color.clear))
        .overlay(Capsule().strokeBorder(note.isStrong ? DesignTokens.noteStrongBorder : DesignTokens.noteMildBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.axis.displayName)
        .accessibilityValue(spokenStrength(note, matchesYou: matchesYou))
    }
}
