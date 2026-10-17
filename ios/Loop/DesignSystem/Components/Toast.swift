import SwiftUI

/// Short confirmations at the top of the screen ("Request sent").
@Observable @MainActor
final class ToastCenter {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let systemImage: String?
    }

    private(set) var current: Toast?
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, systemImage: String? = "checkmark.circle.fill") {
        dismissTask?.cancel()
        withAnimation(.snappy) { current = Toast(message: message, systemImage: systemImage) }
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth) { current = nil }
        }
    }
}

@MainActor struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack {
            if let toast = toasts.current {
                HStack(spacing: 8) {
                    if let symbol = toast.systemImage { Image(systemName: symbol) }
                    Text(toast.message)
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(toast.id)
            }
            Spacer()
        }
        .padding(.top, 8)
        .allowsHitTesting(false)
    }
}
