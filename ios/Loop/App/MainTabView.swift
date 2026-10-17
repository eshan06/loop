import SwiftUI

/// Feed · Saved · [Scan] · Requests · Profile.
/// Scan is a raised black button over a placeholder tab; it opens the scan flow full screen.
/// Pushed screens hide the tab bar, so the raised button only shows at each tab's root.
@MainActor struct MainTabView: View {
    @Environment(Router.self) private var router
    @Environment(NotificationStore.self) private var notifications
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router

        TabView(selection: tabSelection) {
            tabStack(.feed) { FeedView() }
                .tabItem { Label("Feed", systemImage: "square.grid.2x2") }
                .tag(AppTab.feed)

            tabStack(.saved) { SavedView() }
                .tabItem { Label("Saved", systemImage: "heart") }
                .tag(AppTab.saved)

            Color.clear
                .tabItem { Text(" ") }
                .tag(AppTab.scan)

            tabStack(.requests) { RequestsView() }
                .tabItem { Label("Requests", systemImage: "arrow.left.arrow.right") }
                .badge(notifications.unread.requestsBadge)
                .tag(AppTab.requests)

            tabStack(.profile) { ProfileView() }
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .overlay(alignment: .bottom) {
            if (router.paths[router.tab] ?? []).isEmpty {
                ScanTabButton { router.isScanPresented = true }
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.snappy, value: (router.paths[router.tab] ?? []).isEmpty)
        .overlay(alignment: .top) { InAppBannerOverlay() }
        .fullScreenCover(isPresented: $router.isScanPresented) {
            ScanFlowView()
        }
        .onAppear { notifications.start(router: router) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { notifications.start(router: router) } else { notifications.stop() }
        }
    }

    /// Scan isn't a real tab: selecting it opens the scan flow and keeps the current tab.
    private var tabSelection: Binding<AppTab> {
        Binding(get: { router.tab }, set: { newTab in
            if newTab == .scan {
                router.isScanPresented = true
            } else if newTab == router.tab {
                router.popToRoot(newTab)
            } else {
                router.tab = newTab
            }
        })
    }

    private func tabStack<Content: View>(_ tab: AppTab, @ViewBuilder root: () -> Content) -> some View {
        NavigationStack(path: router.path(for: tab)) {
            root()
                .screenBackground()
                .navigationDestination(for: Route.self) { route in
                    RouteView(route: route)
                        .toolbar(.hidden, for: .tabBar)
                }
        }
    }
}

/// Builds the screen for a route.
@MainActor struct RouteView: View {
    let route: Route

    var body: some View {
        screen.screenBackground()
    }

    @ViewBuilder
    private var screen: some View {
        switch route {
        case .listing(let id): ListingDetailView(listingID: id)
        case .thread(let id): ThreadView(requestID: id)
        case .impact: ImpactView()
        case .notifications: NotificationsView()
        case .editListing(let id): EditListingView(listingID: id)
        case .incomingRequests(let listingID, let title): ListingRequestsView(listingID: listingID, title: title)
        }
    }
}

@MainActor private struct ScanTabButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "camera.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Theme.accent, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Scan an item")
        .padding(.bottom, 12)
    }
}
