import SwiftUI

/// The loop glyph: one continuous rounded loop, like an infinity sign.
struct LoopGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        // A lemniscate of Bernoulli, scaled to fit the rect.
        var path = Path()
        let steps = 120
        let a = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let yScale = rect.height / (a * 0.72)
        for step in 0...steps {
            let t = Double(step) / Double(steps) * 2 * .pi
            let denominator = 1 + pow(sin(t), 2)
            let x = a * cos(t) / denominator
            let y = a * sin(t) * cos(t) / denominator * yScale
            let point = CGPoint(x: center.x + x, y: center.y + y)
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

/// Lowercase "loop" in SF Pro Rounded Bold, with the glyph.
@MainActor struct Wordmark: View {
    var size: CGFloat = 34
    /// A Loop Lime highlighter stroke behind the word. Used on the welcome and launch screens.
    var highlight = false

    var body: some View {
        HStack(spacing: size * 0.22) {
            LoopGlyph()
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: size * 0.13, lineCap: .round, lineJoin: .round))
                .frame(width: size * 1.05, height: size * 0.5)
            Text("loop")
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.accent)
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
