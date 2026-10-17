import SwiftUI

/// A neutral text capsule. Share types and "Yours" use the same style; no icons, no color.
@MainActor struct TagCapsule: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? Color.white : Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(filled ? Theme.accent : Theme.surface, in: Capsule())
    }
}

@MainActor struct ShareTypeCapsule: View {
    let shareType: ShareType
    var body: some View { TagCapsule(text: shareType.label) }
}

/// Request status: pending orange, accepted green, declined and cancelled gray, completed black.
@MainActor struct StatusPill: View {
    let status: RequestStatus

    private var color: Color {
        switch status {
        case .pending: Theme.warning
        case .accepted: Theme.success
        case .declined, .cancelled: Color(uiColor: .systemGray)
        case .completed: Theme.accent
        }
    }

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }
}

/// A selectable filter chip: black when selected, `surface` otherwise.
@MainActor struct Chip: View {
    let title: String
    var isSelected = false
    var systemImage: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Theme.accent : Theme.surface, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}
