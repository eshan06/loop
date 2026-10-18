import SwiftUI

/// Lowercase "loop." in SF Pro Rounded Bold: the logo is type only, same as the app icon.
@MainActor struct Wordmark: View {
    var size: CGFloat = 34
    /// A Loop Lime highlighter stroke behind the word. Used on the welcome and launch screens.
    var highlight = false

    var body: some View {
        Text("loop.")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.ink)
            .background(alignment: .bottom) {
                if highlight {
                    Capsule()
                        .fill(Theme.lime)
                        .frame(height: size * 0.34)
                        .rotationEffect(.degrees(-1.5))
                        .padding(.horizontal, -size * 0.08)
                        .offset(y: -size * 0.06)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loop")
    }
}

#Preview {
    VStack(spacing: 40) {
        Wordmark()
        Wordmark(size: 56)
    }
}
