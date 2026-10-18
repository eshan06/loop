import SwiftUI

/// The Loop logo, drawn from the approved artwork's outline (`LoopLogoShape`), so it stays sharp at any size.
/// It is flat: near-black `Theme.ink`, no outline, shadow or gradient.
@MainActor struct Wordmark: View {
    /// Roughly the old wordmark's type size: the logo is `size * 2.9` points wide.
    var size: CGFloat = 34
    /// An optional Loop Lime highlighter stroke behind the logo. Off by default: the logo is meant to stand flat.
    var highlight = false

    var body: some View {
        LoopLogoShape()
            .fill(Theme.ink, style: FillStyle(eoFill: true))
            .aspectRatio(1 / LoopLogoShape.aspect, contentMode: .fit)
            .frame(width: size * 2.9)
            .background(alignment: .bottom) {
                if highlight {
                    Capsule()
                        .fill(Theme.lime)
                        .frame(height: size * 0.34)
                        .rotationEffect(.degrees(-1.5))
                        .padding(.horizontal, -size * 0.08)
                        .offset(y: -size * 0.04)
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
