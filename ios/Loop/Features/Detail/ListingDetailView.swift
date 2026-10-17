import SwiftUI

@MainActor struct ListingDetailView: View {
    let listingID: Int

    @Environment(ListingCache.self) private var cache
    @Environment(SavedStore.self) private var saved
    @Environment(ToastCenter.self) private var toasts
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var error: String?
    @State private var similar: [Listing] = []
    @State private var showRequestSheet = false
    @State private var showStyle = false
    @State private var showReport = false
    @State private var showDelete = false
    @State private var isWorking = false

    private var listing: Listing? { cache[listingID] }

    var body: some View {
        Group {
            if let listing {
                content(listing)
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("Back")
            }
            toolbarContent
        }
        .task { await load() }
        .sheet(isPresented: $showRequestSheet) {
            if let listing { RequestSheet(listing: listing) }
        }
        .sheet(isPresented: $showStyle) {
            if let listing { StyleItSheet(listing: listing) }
        }
        .confirmationDialog("Report this listing", isPresented: $showReport, titleVisibility: .visible) {
            ForEach(["Not clothing", "Inappropriate", "Spam"], id: \.self) { reason in
                Button(reason) { report(reason) }
            }
        } message: {
            Text("Three reports hide a listing from everyone.")
        }
        .confirmationDialog("Delete this listing?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("Its requests and chats are removed too.")
        }
    }

    // MARK: Layout

    private func content(_ listing: Listing) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PhotoCarousel(photos: listing.photos)

                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    header(listing)
                    if let description = listing.description, !description.isEmpty {
                        Text(description).font(.body)
                    }
                    if !listing.tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(listing.tags, id: \.self) { TagCapsule(text: "#\($0)") }
                        }
                    }
                    details(listing)
                    OwnerCard(owner: listing.owner, isMine: listing.isMine)

                    Button {
                        showStyle = true
                    } label: {
                        Label("Style it", systemImage: "sparkles")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Theme.surface, in: Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .foregroundStyle(Theme.textPrimary)

                    if !similar.isEmpty { similarRow }
                }
                .padding(Theme.margin)
                .padding(.bottom, 100)
            }
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { bottomBar(listing) }
    }

    private func header(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(listing.title).font(.title2.bold())
            HStack(spacing: 8) {
                ShareTypeCapsule(shareType: listing.shareType)
                if let size = listing.size { TagCapsule(text: size) }
                TagCapsule(text: listing.condition.label)
                if listing.isMine { TagCapsule(text: "Yours", filled: true) }
            }
        }
    }

    private func details(_ listing: Listing) -> some View {
        VStack(spacing: 0) {
            if let brand = listing.brand { DetailRow(label: "Brand", value: brand) }
            if let color = listing.color { DetailRow(label: "Color", value: color) }
            DetailRow(label: "Category", value: listing.category.label)
            if let spot = listing.meetupSpot { DetailRow(label: "Meetup", value: spot.name, systemImage: "mappin") }
            DetailRow(label: "Impact", value: "\(ImpactFormat.water(listing.impact.waterL)) water saved", systemImage: "drop", isLast: true)
        }
        .cardBackground()
    }

    private var similarRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Similar on campus").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Theme.gutter) {
                    ForEach(similar) { item in
                        NavigationLink(value: Route.listing(item.id)) {
                            ListingCard(listing: cache[item.id] ?? item).frame(width: 140)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
            }
            .scrollClipDisabled()
        }
    }

    // MARK: Bottom bar

    @ViewBuilder
    private func bottomBar(_ listing: Listing) -> some View {
        HStack(spacing: Theme.Space.s) {
            if listing.isMine {
                if listing.status != .completed {
                    SecondaryButton(title: "Edit", systemImage: "pencil") { router.push(.editListing(listing.id)) }
                }
                if listing.pendingRequestCount > 0 {
                    PrimaryButton(title: listing.pendingRequestCount == 1 ? "1 request" : "\(listing.pendingRequestCount) requests") {
                        router.push(.incomingRequests(listingID: listing.id, title: listing.title))
                    }
                } else if let accepted = listing.acceptedRequestId {
                    PrimaryButton(title: "Open chat", systemImage: "bubble.left.and.bubble.right") { router.push(.thread(accepted)) }
                }
            } else {
                switch (listing.myRequestStatus, listing.status) {
                case (.accepted, _):
                    PrimaryButton(title: "Open chat", systemImage: "bubble.left.and.bubble.right") {
                        if let id = listing.myRequestId { router.push(.thread(id)) }
                    }
                case (.pending, _):
                    VStack(spacing: 6) {
                        PrimaryButton(title: "Requested", systemImage: "checkmark", isEnabled: false) {}
                        Button("Cancel request", action: cancelRequest)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                case (.completed, _):
                    PrimaryButton(title: "Exchanged", systemImage: "checkmark.seal", isEnabled: false) {}
                case (_, .active):
                    PrimaryButton(title: "Request", systemImage: "hand.raised") { showRequestSheet = true }
                default:
                    PrimaryButton(title: "No longer available", isEnabled: false) {}
                }
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.Space.s)
        .padding(.bottom, Theme.Space.xs)
        .background(.bar)
        .disabled(isWorking)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let listing {
                if !listing.isMine {
                    HeartButton(isSaved: saved.isSaved(listing)) { saved.toggle(listing, cache: cache, toasts: toasts) }
                }
                Menu {
                    if listing.isMine {
                        if let accepted = listing.acceptedRequestId {
                            Button { router.push(.thread(accepted)) } label: {
                                Label("Mark as exchanged", systemImage: "checkmark.seal")
                            }
                        }
                        if listing.status != .completed {
                            Button(role: .destructive) { showDelete = true } label: { Label("Delete", systemImage: "trash") }
                        }
                    } else {
                        Button(role: .destructive) { showReport = true } label: { Label("Report", systemImage: "flag") }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 32, height: 32)
                        .background(.regularMaterial, in: Circle())
                }
                .accessibilityLabel("More options")
            }
        }
    }

    // MARK: Actions

    private func load() async {
        error = nil
        do {
            let fresh = try await API.client.listing(id: listingID)
            cache.upsert(fresh)
            saved.absorb([fresh])
        } catch {
            if cache[listingID] == nil { self.error = error.userMessage }
        }
        if let items = try? await API.client.similar(listingID: listingID) {
            cache.upsert(items)
            similar = items
        }
    }

    private func cancelRequest() {
        guard let requestID = listing?.myRequestId else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                _ = try await API.client.perform(.cancel, requestID: requestID)
                await load()
                toasts.show("Request cancelled")
            } catch {
                toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func report(_ reason: String) {
        Task {
            do {
                try await API.client.report(listingID: listingID, reason: reason)
                toasts.show("Thanks, we'll take a look.", systemImage: "flag.fill")
            } catch {
                toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }

    private func delete() {
        Task {
            do {
                try await API.client.deleteListing(id: listingID)
                dismiss()
                cache.remove(listingID)
                toasts.show("Listing deleted", systemImage: "trash.fill")
            } catch {
                toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
            }
        }
    }
}

// MARK: - Pieces

@MainActor struct PhotoCarousel: View {
    let photos: [Photo]
    @State private var index = 0

    var body: some View {
        TabView(selection: $index) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                Color.clear
                    .overlay { CachedImage(url: photo.url, maxPixel: 1400) }
                    .clipped()
                    .tag(offset)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: photos.count > 1 ? .automatic : .never))
        .aspectRatio(Theme.photoAspect, contentMode: .fit)
        .background(Theme.surface)
    }
}

@MainActor struct DetailRow: View {
    let label: String
    let value: String
    var systemImage: String?
    var isLast = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(Theme.textSecondary)
                Spacer()
                if let systemImage { Image(systemName: systemImage).foregroundStyle(Theme.textSecondary) }
                Text(value).multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 12)
            if !isLast { Divider().padding(.leading, Theme.Space.m) }
        }
    }
}

@MainActor struct Avatar: View {
    let url: URL?
    let name: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface)
            if let url {
                CachedImage(url: url, maxPixel: size * 3)
            } else {
                Text(initials)
                    .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

@MainActor struct OwnerCard: View {
    let owner: Owner
    var isMine = false

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Avatar(url: owner.avatarUrl, name: owner.displayName, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(isMine ? "You" : owner.displayName).font(.headline)
                Text([owner.dorm, "Shared \(owner.itemsShared) item\(owner.itemsShared == 1 ? "" : "s")"]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Space.m)
        .cardBackground()
    }
}
