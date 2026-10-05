import SwiftUI

/// A bottom toast with an Undo action. The host decides when it disappears
/// (a timer, or only on Undo/Dismiss while VoiceOver is running).
struct UndoToast: View {
    let message: Text
    let onUndo: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            message
                .dsText(.body)
                .foregroundStyle(DesignTokens.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Undo", action: onUndo)
                .dsText(.heading)
                .foregroundStyle(DesignTokens.accent)
                .frame(minWidth: 44, minHeight: 44)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .foregroundStyle(DesignTokens.textSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DesignTokens.surfaceRaised))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(DesignTokens.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}
