import SwiftUI

enum AppTab: Hashable {
    case feed, saved, scan, requests, profile
}

/// Screens pushed onto a tab's NavigationStack.
enum Route: Hashable {
    case listing(Int)
    case thread(Int)
    case impact
    case notifications
    case editListing(Int)
    case incomingRequests(listingID: Int, title: String)
}

/// Owns the selected tab and every tab's navigation path, so notification taps and other
/// deep links can switch tabs and push the right screen.
@Observable @MainActor
final class Router {
    var tab: AppTab = .feed
    var paths: [AppTab: [Route]] = [:]
    var isScanPresented = false
    /// Set after posting so the feed scrolls to the top and animates the new card in.
    var justPostedListingID: Int?
    /// Scroll Profile to badges after a `badge_earned` tap.
    var focusBadges = false

    func path(for tab: AppTab) -> Binding<[Route]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func push(_ route: Route, on tab: AppTab? = nil) {
        let target = tab ?? self.tab
        self.tab = target
        paths[target, default: []].append(route)
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = []
    }

    func open(_ notification: AppNotification) {
        switch notification.type {
        case .requestReceived, .requestAccepted, .requestDeclined, .newMessage:
            guard let requestID = notification.requestId else { return }
            if paths[.requests]?.last == .thread(requestID), tab == .requests { return }
            tab = .requests
            paths[.requests] = [.thread(requestID)]
        case .badgeEarned:
            tab = .profile
            paths[.profile] = []
            focusBadges = true
        }
    }

    /// The thread currently on screen, so a `new_message` banner for it can be skipped.
    var visibleThreadID: Int? {
        if case .thread(let id) = paths[tab]?.last { return id }
        return nil
    }

    func reset() {
        tab = .feed
        paths = [:]
        isScanPresented = false
    }
}
