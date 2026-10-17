import SwiftUI

/// The source of truth for every listing on screen. Feed, detail, saved, and profile read from it,
/// so an edit, delete, save, or status change shows up everywhere at once.
@Observable @MainActor
final class ListingCache {
    private(set) var byID: [Int: Listing] = [:]
    /// Bumped on any change that should make list screens refetch (post, delete, complete).
    private(set) var revision = 0

    subscript(id: Int) -> Listing? { byID[id] }

    func upsert(_ listing: Listing) {
        byID[listing.id] = listing
    }

    func upsert(_ listings: [Listing]) {
        for listing in listings { byID[listing.id] = listing }
    }

    func remove(_ id: Int) {
        byID[id] = nil
        revision += 1
    }

    func update(_ id: Int, _ change: (inout Listing) -> Void) {
        guard var listing = byID[id] else { return }
        change(&listing)
        byID[id] = listing
    }

    func invalidate() {
        revision += 1
    }

    /// The freshest copy of each listing in a list.
    func resolve(_ ids: [Int]) -> [Listing] {
        ids.compactMap { byID[$0] }
    }

    func clear() {
        byID = [:]
        revision += 1
    }
}
