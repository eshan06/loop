import SwiftUI

@main
@MainActor struct LoopApp: App {
    @State private var session = SessionStore()
    @State private var router = Router()
    @State private var listings = ListingCache()
    @State private var saved = SavedStore()
    @State private var notifications = NotificationStore()
    @State private var toasts = ToastCenter()

    init() {
        ImageLoader.configureURLCache()
        // `-resetSession YES` starts signed out (UI tests, demo rehearsals).
        if UserDefaults.standard.bool(forKey: "resetSession") { AuthToken.set(nil) }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(router)
                .environment(listings)
                .environment(saved)
                .environment(notifications)
                .environment(toasts)
                .tint(Theme.accent)
                .preferredColorScheme(.light)
        }
    }
}
