import SwiftUI

@Observable @MainActor
final class FeedModel {
    var shareType: ShareType?
    var category: ItemCategory?
    var size: String?
    var searchText = ""

    private(set) var ids: [Int] = []
    private(set) var state: LoadState = .idle
    private(set) var campus: CampusImpact?
    /// The listing just published, highlighted in Loop Lime for a few seconds.
    var highlightedID: Int?

    var activeFilterCount: Int { (category == nil ? 0 : 1) + (size == nil ? 0 : 1) }
    var isSearchingOrFiltered: Bool { activeFilterCount > 0 || !searchText.trimmingCharacters(in: .whitespaces).isEmpty }

    private var query: ListingQuery {
        ListingQuery(shareType: shareType, category: category, size: size,
                     q: searchText.trimmingCharacters(in: .whitespaces), limit: 50)
    }

    /// Loads the first 50 listings (seed data is 30 to 40, so the feed doesn't page further).
    func load(cache: ListingCache, saved: SavedStore) async {
        if ids.isEmpty { state = .loading }
        do {
            let page = try await API.client.listings(query)
            cache.upsert(page.items)
            saved.absorb(page.items)
            withAnimation(.snappy) { ids = page.items.map(\.id) }
            state = .loaded
        } catch {
            guard !error.isCancellation else { return }
            if ids.isEmpty { state = .failed(error.userMessage) }
        }
    }

    func loadCampus() async {
        if let campus = try? await API.client.campusImpact() { self.campus = campus }
    }

    /// Put a just-posted listing at the top without waiting for a refresh.
    func insertAtTop(_ id: Int) {
        guard !ids.contains(id) else { return }
        withAnimation(.spring(duration: 0.5, bounce: 0.3)) { ids.insert(id, at: 0) }
    }

    func remove(missingFrom cache: ListingCache) {
        ids.removeAll { id in
            guard let listing = cache[id] else { return true }
            return listing.status != .active
        }
    }
}
