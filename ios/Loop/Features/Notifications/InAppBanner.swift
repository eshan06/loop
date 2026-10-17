import SwiftUI

/// A push-style banner for notifications that arrive while the app is open.
/// Tap opens the right screen; swipe up dismisses.
struct InAppBannerOverlay: View {
    @Environment(NotificationStore.self) private var notifications
    @Environment(Router.self) private var router
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        VStack {
            if let banner = notifications.banner {
                Button {
                    notifications.markRead(banner.notification)
                    notifications.dismissBanner()
                    router.open(banner.notification)
                } label: {
                    BannerContent(notification: banner.notification, others: banner.others)
                }
                .buttonStyle(.plain)
                .offset(y: min(0, dragOffset))
                .gesture(
                    DragGesture()
                        .onChanged { dragOffset = $0.translation.height }
                        .onEnded { value in
                            if value.translation.height < -24 { notifications.dismissBanner() }
                            withAnimation(.snappy) { dragOffset = 0 }
                        }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .id(banner.notification.id)
                .sensoryFeedback(.impact(weight: .light), trigger: banner.notification.id)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
    }
}

private struct BannerContent: View {
    let notification: AppNotification
    let others: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notification.type.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(notification.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text("now").font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if let body = notification.body {
                    Text(body).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                if others > 0 {
                    Text("+\(others) more").font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
        .contentShape(Rectangle())
    }
}
