import SwiftUI

@MainActor struct FeedView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ListingCache.self) private var cache
    @Environment(SavedStore.self) private var saved
    @Environment(NotificationStore.self) private var notifications

    @State private var model = FeedModel()
    @State private var showFilters = false
    @State private var postedTrigger = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    Color.clear.frame(height: 0).id("top")
                    chipRow
                    content
                }
                .padding(.bottom, 96)
            }
            .refreshable {
                async let feed: () = model.load(cache: cache, saved: saved)
                async let campus: () = model.loadCampus()
                _ = await (feed, campus)
            }
            .onChange(of: router.justPostedListingID) { _, id in
                guard let id else { return }
                // A filter or search could hide the new card, so clear them first.
                model.shareType = nil
                model.category = nil
                model.size = nil
                model.searchText = ""
                withAnimation(.snappy) { proxy.scrollTo("top", anchor: .top) }
                model.insertAtTop(id)
                model.highlightedID = id
                postedTrigger += 1
                router.justPostedListingID = nil
                Task {
                    try? await Task.sleep(for: .seconds(6))
                    if model.highlightedID == id { withAnimation(.smooth) { model.highlightedID = nil } }
                }
            }
        }
        .navigationTitle("Feed")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Text(session.user?.campus.name ?? "")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            ToolbarItem(placement: .topBarTrailing) { BellButton() }
        }
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Search brands, styles, tags")
        .sheet(isPresented: $showFilters) {
            FilterSheet(category: $model.category, size: $model.size)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(Theme.Radius.sheet)
                .presentationBackground(Theme.background)
        }
        .task(id: FilterKey(shareType: model.shareType, category: model.category, size: model.size, search: model.searchText)) {
            // Wait 300 ms after the last keystroke before searching.
            if !model.searchText.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            await model.load(cache: cache, saved: saved)
        }
        .task { await model.loadCampus() }
        .onChange(of: cache.revision) { _, _ in
            model.remove(missingFrom: cache)
            Task { await model.load(cache: cache, saved: saved) }
        }
        .sensoryFeedback(.success, trigger: postedTrigger)
    }

    private struct FilterKey: Equatable {
        let shareType: ShareType?
        let category: ItemCategory?
        let size: String?
        let search: String
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Chip(title: "All", isSelected: model.shareType == nil) { model.shareType = nil }
                ForEach(ShareType.allCases) { type in
                    Chip(title: type.label, isSelected: model.shareType == type) {
                        model.shareType = model.shareType == type ? nil : type
                    }
                }
                Chip(title: model.activeFilterCount > 0 ? "Filters · \(model.activeFilterCount)" : "Filters",
                     isSelected: model.activeFilterCount > 0, systemImage: "chevron.down") {
                    showFilters = true
                }
            }
            .padding(.horizontal, Theme.margin)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var content: some View {
        let listings = cache.resolve(model.ids)
        switch model.state {
        case .idle, .loading where listings.isEmpty:
            ListingGridSkeleton().padding(.horizontal, Theme.margin)
        case .failed(let message) where listings.isEmpty:
            ErrorState(message: message) { Task { await model.load(cache: cache, saved: saved) } }
                .padding(.top, 60)
        default:
            if !model.isSearchingOrFiltered, let campus = model.campus {
                CampusBanner(campus: campus) { router.push(.impact, on: .feed) }
                    .padding(.horizontal, Theme.margin)
            }
            if listings.isEmpty {
                emptyState.padding(.top, 40)
            } else {
                ListingGrid(listings: listings, highlightID: model.highlightedID)
                    .padding(.horizontal, Theme.margin)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.isSearchingOrFiltered || model.shareType != nil {
            EmptyState(systemImage: "magnifyingglass", title: "No matches",
                       message: "Try a different search or clear the filters.",
                       actionTitle: "Clear filters") {
                model.shareType = nil
                model.category = nil
                model.size = nil
                model.searchText = ""
            }
        } else {
            EmptyState(systemImage: "tshirt", title: "Nothing here yet",
                       message: "Be the first to share something from \(session.user?.dorm ?? "your dorm").",
                       actionTitle: "Scan an item") { router.isScanPresented = true }
        }
    }
}

/// "86 items rehomed this week · 61 kg kept out of landfill". Opens the Impact screen.
@MainActor struct CampusBanner: View {
    let campus: CampusImpact
    let action: () -> Void

    private var bannerDetail: String {
        var parts = ["\(ImpactFormat.mass(campus.textileKg)) kept out of landfill"]
        if let topDorm = campus.topDorm { parts.append("\(topDorm) leads") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: "arrow.3.trianglepath")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(Theme.background, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    (Text("\(campus.itemsRehomed)").font(.roundedNumber(16)) + Text(" items rehomed this week"))
                        .font(.subheadline.weight(.medium))
                    Text(bannerDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Space.s)
            .cardBackground()
        }
        .buttonStyle(PressableStyle())
    }
}

/// The bell with an unread count; pushes the notification list.
@MainActor struct BellButton: View {
    @Environment(NotificationStore.self) private var notifications
    @Environment(Router.self) private var router

    var body: some View {
        Button {
            router.push(.notifications)
        } label: {
            Image(systemName: notifications.unread.notifications > 0 ? "bell.badge" : "bell")
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.bounce, value: notifications.unread.notifications)
                .overlay(alignment: .topTrailing) {
                    if notifications.unread.notifications > 0 {
                        Text("\(notifications.unread.notifications)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: Double(notifications.unread.notifications)))
                            .padding(.horizontal, 5)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(Theme.destructive, in: Capsule())
                            .offset(x: 9, y: -8)
                    }
                }
        }
        .accessibilityLabel("Notifications, \(notifications.unread.notifications) unread")
    }
}
