import SwiftUI

@MainActor struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ListingCache.self) private var cache
    @Environment(SavedStore.self) private var saved
    @Environment(NotificationStore.self) private var notifications

    var body: some View {
        ZStack {
            switch session.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                SignInView()
                    .transition(.opacity)
            case .needsSetup:
                ProfileSetupView()
                    .transition(.move(edge: .trailing))
            case .signedIn:
                MainTabView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: session.phase)
        .overlay { ToastOverlay() }
        .task { await session.restore() }
        .onChange(of: session.phase) { _, phase in
            if phase != .signedIn {
                notifications.reset()
                router.reset()
                cache.clear()
                saved.clear()
            }
        }
    }
}

@MainActor private struct LaunchView: View {
    var body: some View {
        Wordmark(size: 44, highlight: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}
