import SwiftUI

/// Polls notifications every 5 seconds while the app is in the foreground and signed in.
/// It drives the bell, the Requests tab badge, and the in-app banner.
@Observable @MainActor
final class NotificationStore {
    private(set) var items: [AppNotification] = []
    private(set) var unread: Unread = .zero
    /// The newest notification to show as a banner, plus how many others arrived with it.
    private(set) var banner: (notification: AppNotification, others: Int)?
    /// Bumped whenever a request-related notification arrives, so request screens refresh.
    private(set) var requestsRevision = 0
    /// The latest badge_earned notification, for screens that care.
    private(set) var lastBadgeID: Int?

    /// Unread notification IDs already seen, with the `created_at` we saw. A `new_message` notification
    /// collapses (docs/API.md): more messages update the same row, keeping its `id` but moving
    /// `created_at`, so a later date counts as fresh too.
    private var seen: [Int: Date]?
    private var pollTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    static let interval: Duration = .seconds(5)
    /// How long the in-app banner stays up. UI tests (`-uiTesting YES`) keep it longer so they can find it.
    static let bannerSeconds: Double = UserDefaults.standard.bool(forKey: "uiTesting") ? 15 : 4

    func start(router: Router) {
        guard pollTask == nil else { return }
        pollTask = Task {
            while !Task.isCancelled {
                await poll(router: router)
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func reset() {
        stop()
        items = []
        unread = .zero
        banner = nil
        seen = nil
    }

    func poll(router: Router) async {
        async let pageResult = try? API.client.notifications()
        async let unreadResult = try? API.client.unread()
        let (page, counts) = await (pageResult, unreadResult)
        if let counts { unread = counts }
        guard let page else { return }
        items = page.items
        if counts == nil { unread.notifications = page.unread }

        let unreadNow = page.items.filter { !$0.read }
        let previous = seen
        defer { seen = Dictionary(uniqueKeysWithValues: unreadNow.map { ($0.id, $0.createdAt) }).merging(seen ?? [:]) { new, _ in new } }
        // The first poll after launch only sets the starting point.
        guard let previous else { return }
        let fresh = Self.freshItems(in: unreadNow, previous: previous)
        guard !fresh.isEmpty else { return }

        if fresh.contains(where: { $0.type != .badgeEarned }) { requestsRevision += 1 }
        if let badge = fresh.first(where: { $0.type == .badgeEarned }) { lastBadgeID = badge.id }

        let visible = fresh.filter { notification in
            !(notification.type == .newMessage && notification.requestId == router.visibleThreadID)
        }
        if let newest = visible.first { showBanner(newest, others: visible.count - 1) }
    }

    /// Unread notifications that are new since `previous`: an ID we haven't seen, or a collapsed
    /// `new_message` whose `created_at` moved forward.
    nonisolated static func freshItems(in unread: [AppNotification], previous: [Int: Date]) -> [AppNotification] {
        unread.filter { item in
            guard let before = previous[item.id] else { return true }
            return item.createdAt > before
        }
    }

    private func showBanner(_ notification: AppNotification, others: Int) {
        bannerTask?.cancel()
        withAnimation(.snappy) { banner = (notification, others) }
        bannerTask = Task {
            try? await Task.sleep(for: .seconds(Self.bannerSeconds))
            guard !Task.isCancelled else { return }
            dismissBanner()
        }
    }

    func dismissBanner() {
        withAnimation(.smooth) { banner = nil }
    }

    func markRead(_ notification: AppNotification) {
        guard !notification.read else { return }
        if let index = items.firstIndex(where: { $0.id == notification.id }) { items[index].read = true }
        unread.notifications = max(0, unread.notifications - 1)
        Task { try? await API.client.markNotificationsRead(ids: [notification.id]) }
    }

    func markAllRead() {
        guard unread.notifications > 0 || items.contains(where: { !$0.read }) else { return }
        items = items.map { var item = $0; item.read = true; return item }
        unread.notifications = 0
        Task { try? await API.client.markNotificationsRead(ids: nil) }
    }

    /// Refresh the counts right away (after reading a chat, accepting a request, and so on).
    func refreshCounts() {
        Task {
            if let counts = try? await API.client.unread() { unread = counts }
        }
    }
}
