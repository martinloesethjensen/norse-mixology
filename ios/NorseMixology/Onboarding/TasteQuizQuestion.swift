import NorseMixologyCore

/// The 5 onboarding quiz questions, presented in this fixed order (no
/// randomisation — see the Phase 11 spec's onboarding checklist). Choosing
/// left sets the axis to 0.85; choosing right sets it to 0.15.
struct TasteQuizQuestion: Identifiable {
    let id: Int
    let axis: WritableKeyPath<UserTasteProfile, Double>
    let leftLabel: String
    let rightLabel: String

    static let all: [TasteQuizQuestion] = [
        TasteQuizQuestion(id: 0, axis: \.sweetness, leftLabel: "Sweet 🍬", rightLabel: "Dry 🍋"),
        TasteQuizQuestion(id: 1, axis: \.bitterness, leftLabel: "Bitter & Bold", rightLabel: "Smooth & Mellow"),
        TasteQuizQuestion(id: 2, axis: \.citrus, leftLabel: "Bright & Citrusy", rightLabel: "Rich & Deep"),
        TasteQuizQuestion(id: 3, axis: \.smokiness, leftLabel: "Smoky & Peaty", rightLabel: "Clean & Crisp"),
        TasteQuizQuestion(id: 4, axis: \.herbal, leftLabel: "Herbal & Botanical", rightLabel: "Simple & Spirit-forward"),
    ]
}
