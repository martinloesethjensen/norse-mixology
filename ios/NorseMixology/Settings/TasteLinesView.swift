import SwiftUI
import NorseMixologyCore

/// "Your taste" in Settings: one line per quiz question, between its two
/// answers, with the "you" diamond where the answer landed. Replaces the
/// five dots, which looked exactly like an ingredient's.
struct TasteLinesView: View {
    let profile: UserTasteProfile

    private var hasPreference: Bool { TasteRanking.isActive(profile) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(FlavorAxis.allCases.enumerated()), id: \.element) { index, axis in
                line(axis)
                if index < FlavorAxis.allCases.count - 1 {
                    Divider().overlay(DesignTokens.border)
                }
            }
        }
    }

    private func line(_ axis: FlavorAxis) -> some View {
        let value = axis.value(in: profile)
        let leaning = TasteFit.lean(of: profile, on: axis)
        let answer: String? = {
            guard hasPreference else { return nil }
            switch leaning {
            case .toward: return axis.highPole
            case .away: return axis.lowPole
            case .neutral: return nil
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(axis.settingsTitle)
                    .dsText(.heading)
                    .foregroundStyle(DesignTokens.textPrimary)
                Spacer(minLength: 8)
                if let answer {
                    Text(answer)
                        .dsText(.body)
                        .foregroundStyle(DesignTokens.noteStrongText)
                        .multilineTextAlignment(.trailing)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(DesignTokens.noteMildBorder).frame(height: 2)
                    YouMarker(size: 8, fill: DesignTokens.surface)
                        .opacity(hasPreference ? 1 : 0.45)
                        .position(x: (hasPreference ? max(0, min(1, value)) : 0.5) * geometry.size.width,
                                  y: geometry.size.height / 2)
                }
            }
            .frame(height: 16)
            HStack(alignment: .top) {
                Text(axis.lowPole)
                Spacer(minLength: 12)
                Text(axis.highPole).multilineTextAlignment(.trailing)
            }
            .dsText(.body)
            .foregroundStyle(DesignTokens.textSecondary)
        }
        .padding(.vertical, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(axis.settingsTitle)
        .accessibilityValue(answer.map { Text(verbatim: $0) } ?? Text("No preference yet"))
    }
}
