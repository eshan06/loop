import SwiftUI

/// Empty list: symbol, one-line title, one-line body, optional action.
@MainActor struct EmptyState: View {
    let systemImage: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message { Text(message) }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }
}

/// Error with the server's message and a Retry button.
@MainActor struct ErrorState: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Something went wrong", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
        }
    }
}

/// Where a list's data is.
enum LoadState: Equatable {
    case idle, loading, loaded, failed(String)
}

// MARK: - Shimmer

/// A light sweep over redacted placeholders.
struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                GeometryReader { proxy in
                    LinearGradient(colors: [.clear, .white.opacity(0.6), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.6)
                        .offset(x: phase * proxy.size.width * 1.6)
                }
                .mask(content)
                .allowsHitTesting(false)
            }
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View {
        modifier(ShimmerIf(active: active))
    }
}

private struct ShimmerIf: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.modifier(Shimmer()) } else { content }
    }
}

/// A gray rounded block for skeleton layouts.
@MainActor struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat = 14
    var radius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(Color(uiColor: .systemGray5))
            .frame(width: width, height: height)
    }
}
