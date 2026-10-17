import SwiftUI

@MainActor struct SavedView: View {
    @Environment(ListingCache.self) private var cache
    @Environment(SavedStore.self) private var saved

    @State private var ids: [Int]?
    @State private var error: String?

    /// Hearts toggled off elsewhere disappear right away.
    private var listings: [Listing] {
        cache.resolve(ids ?? []).filter { saved.ids.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            if ids == nil, let error {
                ErrorState(message: error) { Task { await load() } }.padding(.top, 80)
            } else if ids == nil {
                ListingGridSkeleton(count: 4).padding(Theme.margin)
            } else if listings.isEmpty {
                EmptyState(systemImage: "heart", title: "Nothing saved yet",
                           message: "Tap the heart on anything you like.")
                    .padding(.top, 80)
            } else {
                ListingGrid(listings: listings)
                    .padding(Theme.margin)
                    .padding(.bottom, 96)
            }
        }
        .navigationTitle("Saved")
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: saved.revision) { _, _ in Task { await load() } }
    }

    private func load() async {
        do {
            let page = try await API.client.savedListings()
            cache.upsert(page.items)
            saved.absorb(page.items)
            withAnimation(.snappy) { ids = page.items.map(\.id) }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
    }
}
