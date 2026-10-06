import SwiftUI

/// The diamond that means "you" — where the taste quiz says you land, or a
/// chip for a flavour you lean toward (Tasting Dots design). Always the same
/// shape so it never needs a legend after the first time.
struct YouMarker: View {
    var size: CGFloat = 8
    var fill: Color = DesignTokens.surface

    /// Grows with Dynamic Type, but only a little: it must stay readable beside
    /// large text without outgrowing the 8 pt bar it sits on.
    @ScaledMetric(relativeTo: .footnote) private var textScale: CGFloat = 1

    private var scaledSize: CGFloat { size * min(textScale, 1.6) }

    var body: some View {
        Rectangle()
            .fill(fill)
            .overlay(Rectangle().strokeBorder(DesignTokens.textPrimary, lineWidth: 2))
            .frame(width: scaledSize, height: scaledSize)
            .rotationEffect(.degrees(45))
            .padding(scaledSize * 0.21) // the rotated corners reach past the frame
            .accessibilityHidden(true)
    }
}
