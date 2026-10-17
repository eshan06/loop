import SwiftUI

/// Edit my listing: the Review form without the AI, saved with PATCH /listings/{id}.
@MainActor struct EditListingView: View {
    let listingID: Int

    @Environment(ListingCache.self) private var cache
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss

    @State private var form = ListingFormState()
    @State private var spots: [MeetupSpot]?
    @State private var isSaving = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            ShareFields(form: $form, spots: spots)
            ListingDetailsFields(form: $form)
            if let error {
                Section { Text(error).foregroundStyle(Theme.destructive) }
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .navigationTitle("Edit listing")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else { Button("Save", action: save).bold().disabled(!form.isValid) }
            }
        }
        .task {
            if !loaded, let listing = cache[listingID] {
                form = ListingFormState(listing)
                loaded = true
            }
            spots = (try? await API.client.meetupSpots()) ?? []
        }
    }

    private func save() {
        guard let listing = cache[listingID], let input = form.input(photoIDs: listing.photos.map(\.id)) else { return }
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                let updated = try await API.client.updateListing(id: listingID, input)
                cache.upsert(updated)
                toasts.show("Saved")
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}
