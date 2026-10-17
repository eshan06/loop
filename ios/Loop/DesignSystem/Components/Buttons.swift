import SwiftUI

/// Full-width black capsule, 50 pt tall, with a loading state.
@MainActor struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else {
                    Label {
                        Text(title)
                    } icon: {
                        if let systemImage { Image(systemName: systemImage) }
                    }
                    .labelStyle(.titleAndIcon)
                }
            }
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(isEnabled ? Theme.accent : Color(uiColor: .systemGray3), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(!isEnabled || isLoading)
    }
}

/// Outlined or tinted secondary capsule button.
@MainActor struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var role: ButtonRole?
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.headline)
            .foregroundStyle(role == .destructive ? Theme.destructive : Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// Scales down slightly while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.snappy(duration: 0.2), value: configuration.isPressed)
    }
}

/// A round icon button on a material circle, used over photos.
@MainActor struct CircleIconButton: View {
    let systemImage: String
    var tint: Color = Theme.textPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle())
    }
}
