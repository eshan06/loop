import SwiftUI

@MainActor struct NotificationsView: View {
    @Environment(NotificationStore.self) private var notifications
    @Environment(Router.self) private var router

    var body: some View {
        Group {
            if notifications.items.isEmpty {
                EmptyState(systemImage: "bell", title: "No notifications",
                           message: "Requests, replies, and badges show up here.")
            } else {
                List(notifications.items) { item in
                    Button {
                        notifications.markRead(item)
                        router.open(item)
                    } label: {
                        NotificationRow(notification: item)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await notifications.poll(router: router) }
        .task {
            // Mark everything read a moment after the list opens.
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            notifications.markAllRead()
        }
    }
}

@MainActor private struct NotificationRow: View {
    let notification: AppNotification

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Image(systemName: notification.type.symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Theme.surface, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.title).font(.subheadline.weight(notification.read ? .regular : .semibold))
                if let body = notification.body {
                    Text(body).font(.subheadline).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                Text(notification.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            if !notification.read {
                Circle().fill(Theme.accent).frame(width: 8, height: 8).padding(.top, 6)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
