import SwiftUI

/// One quiz question: a two-half card that responds to a left/right drag
/// **and** exposes each half as an independently tappable, VoiceOver-
/// focusable button — never gesture-only (Phase 6 hardening rule).
struct ThisOrThatCard: View {
    enum Choice { case left, right }

    let question: TasteQuizQuestion
    let onChoose: (Choice) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false

    private let dragCommitThreshold: CGFloat = 80

    var body: some View {
        HStack(spacing: 1) {
            choiceHalf(.left, label: question.leftLabel)
            choiceHalf(.right, label: question.rightLabel)
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(DesignTokens.border, lineWidth: 1)
        )
        .offset(x: dragOffset)
        .rotationEffect(.degrees(dragOffset / 20))
        .simultaneousGesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    dragOffset = value.translation.width
                }
                .onEnded { value in
                    isDragging = false
                    if value.translation.width > dragCommitThreshold {
                        onChoose(.right)
                    } else if value.translation.width < -dragCommitThreshold {
                        onChoose(.left)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        dragOffset = 0
                    }
                }
        )
        .animation(.interactiveSpring(), value: dragOffset)
    }

    @ViewBuilder
    private func choiceHalf(_ choice: Choice, label: String) -> some View {
        Button {
            onChoose(choice)
        } label: {
            Text(label)
                .dsText(.heading)
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.surface)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Double tap to choose")
    }
}

#Preview {
    ThisOrThatCard(question: TasteQuizQuestion.all[0]) { _ in }
        .padding()
        .dsScreenBackground()
}
