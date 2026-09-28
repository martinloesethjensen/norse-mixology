import SwiftUI

/// A system-symbol icon with a slow, looping vertical drift — used inside
/// empty states (`ContentUnavailableView`'s closure-based `label:`) so the
/// float is isolated to the icon and never touches title/description/action
/// text. Freezes at rest under Reduce Motion rather than being removed, so
/// the icon doesn't look mid-animation or offset.
struct FloatingIcon: View {
    let systemName: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFloating = false

    var body: some View {
        Image(systemName: systemName)
            .offset(y: reduceMotion ? 0 : (isFloating ? -2.5 : 2.5))
            .animation(reduceMotion ? nil : .easeInOut(duration: 3).repeatForever(autoreverses: true), value: isFloating)
            .onAppear { isFloating = true }
    }
}
