import SwiftUI

/// The recipe header backdrop: the first photo, blurred and washed with the
/// screen's own background colour so title text keeps its contrast on any photo
/// (a 78% wash leaves roughly 9:1 even under a pure-white photo in dark mode).
/// Plain with no photo, or when Reduce Transparency is on.
struct TakeHeaderBackground: View {
    let thumbnail: Data?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if let thumbnail, !reduceTransparency, let image = UIImage(data: thumbnail) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .blur(radius: 24)
                .overlay(DesignTokens.background.opacity(0.78))
                .frame(maxWidth: .infinity)
                .frame(height: 340)
                .clipped()
                .mask(
                    LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
                )
                .accessibilityHidden(true)
        }
    }
}
