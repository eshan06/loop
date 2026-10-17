import SwiftUI

/// Saved listing IDs. Toggling the heart anywhere updates every view at once.
/// Toggles are optimistic and roll back if the call fails.
@Observable @MainActor
final class SavedStore {
    private(set) var ids: Set<Int> = []
    private(set) var revision = 0

    func isSaved(_ listing: Listing) -> Bool { ids.contains(listing.id) }

    /// Seed from listings the server says are saved.
    func absorb(_ listings: [Listing]) {
        for listing in listings {
            if listing.savedByMe { ids.insert(listing.id) } else { ids.remove(listing.id) }
        }
    }

    func toggle(_ listing: Listing, cache: ListingCache, toasts: ToastCenter) {
        let saving = !ids.contains(listing.id)
        set(saving, listing.id, cache: cache)
        Task {
            do {
                try await API.client.setSaved(saving, listingID: listing.id)
                revision += 1
            } catch {
                set(!saving, listing.id, cache: cache)
                toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func set(_ saved: Bool, _ id: Int, cache: ListingCache) {
        if saved { ids.insert(id) } else { ids.remove(id) }
        cache.update(id) { $0.savedByMe = saved }
    }

    func clear() {
        ids = []
    }
}
