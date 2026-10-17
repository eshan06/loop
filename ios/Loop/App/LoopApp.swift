import SwiftUI

@main
struct LoopApp: App {
    @State private var session = SessionStore()
    @State private var router = Router()
    @State private var listings = ListingCache()
    @State private var saved = SavedStore()
    @State private var notifications = NotificationStore()
    @State private var toasts = ToastCenter()

    init() {
        ImageLoader.configureURLCache()
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
