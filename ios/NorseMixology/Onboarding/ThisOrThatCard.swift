import SwiftUI

/// One quiz question: a two-half card that responds to a left/right drag
/// **and** exposes each half as an independently VoiceOver-focusable
/// element — never gesture-only (Phase 6 hardening rule).
///
/// A single `DragGesture(minimumDistance: 0)` owns all touch interaction —
/// both a plain tap and a full swipe resolve through the same `onEnded`.
/// This is deliberate: two earlier attempts used a `Button` per half
/// alongside a separate drag gesture, and however they were combined
/// (`.gesture` blocked taps entirely; `.simultaneousGesture` let both
/// recognizers fire from one physical touch, sometimes reporting opposite
/// choices for the same swipe). A single recognizer removes the race by
/// construction — there is only ever one source of truth. VoiceOver
/// bypasses touch entirely and invokes `accessibilityAction` directly, so
/// each half is still a fully accessible, independently activatable
/// element without needing a real `Button`.
struct ThisOrThatCard: View {
    enum Choice { case left, right }

    let question: TasteQuizQuestion
    let onChoose: (Choice) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var cardWidth: CGFloat = 0

    private let dragCommitThreshold: CGFloat = 80
    private let tapMovementThreshold: CGFloat = 10

    var body: some View {
        HStack(spacing: 1) {
            choiceHalf(.left, label: question.leftLabel)
            choiceHalf(.right, label: question.rightLabel)
        }
        .frame(minHeight: 220)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newWidth in cardWidth = newWidth }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DesignTokens.border, lineWidth: 1)
        )
        .offset(x: dragOffset)
        .rotationEffect(.degrees(dragOffset / 20))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    if let choice = resolve(value) {
                        // Committed (tap or a swipe past the threshold): leave
                        // `dragOffset` as-is rather than snapping it back to 0,
                        // so the card keeps moving in the direction it was
                        // swiped as `TasteOnboardingView` removes it — a plain
                        // tap never moved `dragOffset` away from 0 anyway, so
                        // this only visibly matters for a real swipe.
                        onChoose(choice)
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .animation(.interactiveSpring(), value: dragOffset)
    }

    /// The single decision point for what a completed touch means: a tap
    /// resolves by which half it started in; a committed drag resolves by
    /// direction; anything else (a drag that didn't clear the threshold)
    /// is a cancelled gesture — `nil` — and the card springs back to center.
    private func resolve(_ value: DragGesture.Value) -> Choice? {
        let translation = value.translation.width
        if abs(translation) < tapMovementThreshold {
            return (cardWidth > 0 && value.startLocation.x > cardWidth / 2) ? .right : .left
        } else if translation > dragCommitThreshold {
            return .right
        } else if translation < -dragCommitThreshold {
            return .left
        }
        return nil
    }

    @ViewBuilder
    private func choiceHalf(_ choice: Choice, label: String) -> some View {
        Text(label)
            .dsText(.heading)
            .foregroundStyle(DesignTokens.textPrimary)
            .multilineTextAlignment(.center)
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DesignTokens.surface)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to choose")
            .accessibilityAction { onChoose(choice) }
    }
}

#Preview {
    ThisOrThatCard(question: TasteQuizQuestion.all[0]) { _ in }
        .padding()
        .dsScreenBackground()
}
