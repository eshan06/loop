import SwiftUI

/// Send a request with an optional note (280 characters max).
@MainActor struct RequestSheet: View {
    let listing: Listing

    @Environment(\.dismiss) private var dismiss
    @Environment(ListingCache.self) private var cache
    @Environment(ToastCenter.self) private var toasts
    @State private var note = ""
    @State private var isSending = false
    @State private var error: String?
    @State private var sent = 0
    @FocusState private var focused: Bool

    private let limit = 280

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                HStack(spacing: Theme.Space.s) {
                    CachedImage(url: listing.coverURL, maxPixel: 200)
                        .frame(width: 52, height: 65)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(listing.title).font(.headline).lineLimit(2)
                        Text("\(listing.owner.displayName) · \(listing.shareType.label)")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                }

                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Add a note (optional)", text: $note, axis: .vertical)
                        .lineLimit(4...8)
                        .focused($focused)
                        .padding(Theme.Space.s)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                        .onChange(of: note) { _, value in
                            if value.count > limit { note = String(value.prefix(limit)) }
                        }
                    Text("\(note.count)/\(limit)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }

                if let error {
                    Text(error).font(.footnote).foregroundStyle(Theme.destructive)
                }
                Spacer()
                PrimaryButton(title: "Send request", systemImage: "paperplane.fill", isLoading: isSending, action: send)
            }
            .padding(Theme.margin)
            .navigationTitle("Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .presentationCornerRadius(Theme.Radius.sheet)
        .presentationBackground(Theme.background)
        .onAppear { focused = true }
        .sensoryFeedback(.success, trigger: sent)
    }

    private func send() {
        isSending = true
        error = nil
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSending = false }
            do {
                let request = try await API.client.requestListing(id: listing.id, note: trimmed.isEmpty ? nil : trimmed)
                cache.update(listing.id) {
                    $0.myRequestStatus = request.status
                    $0.myRequestId = request.id
                }
                sent += 1
                toasts.show("Request sent")
                dismiss()
            } catch {
                if error.apiCode == "already_requested" {
                    if let fresh = try? await API.client.listing(id: listing.id) { cache.upsert(fresh) }
                    dismiss()
                } else {
                    self.error = error.userMessage
                }
            }
        }
    }
}
