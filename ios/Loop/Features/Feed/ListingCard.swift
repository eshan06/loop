import SwiftUI

/// A feed card: 4:5 photo, title, size, share-type capsule, and "Yours" on my own items.
@MainActor struct ListingCard: View {
    let listing: Listing

    @Environment(SavedStore.self) private var saved
    @Environment(ListingCache.self) private var cache
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear
                .aspectRatio(Theme.photoAspect, contentMode: .fit)
                .overlay { CachedImage(url: listing.coverURL, maxPixel: 500) }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                .overlay { PhotoHairline(radius: Theme.Radius.card) }
                .overlay(alignment: .topTrailing) {
                    if !listing.isMine {
                        HeartButton(isSaved: saved.isSaved(listing)) {
                            saved.toggle(listing, cache: cache, toasts: toasts)
                        }
                        .padding(8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if listing.status == .pending {
                        TagCapsule(text: "On hold", filled: true).padding(8)
                    }
                }

            Text(listing.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            HStack(spacing: 6) {
                if let size = listing.size {
                    Text(size)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                ShareTypeCapsule(shareType: listing.shareType)
                if listing.isMine { TagCapsule(text: "Yours") }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("listingCard")
    }
}

@MainActor struct HeartButton: View {
    let isSaved: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isSaved ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: Circle())
                .symbolEffect(.bounce, value: isSaved)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: isSaved)
        .accessibilityLabel(isSaved ? "Unsave" : "Save")
    }
}

/// Two-column grid of listing cards that push item detail.
@MainActor struct ListingGrid: View {
    let listings: [Listing]
    var highlightID: Int?

    private let columns = [GridItem(.flexible(), spacing: Theme.gutter, alignment: .top),
                           GridItem(.flexible(), spacing: Theme.gutter, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: Theme.Space.l) {
            ForEach(listings) { listing in
                NavigationLink(value: Route.listing(listing.id)) {
                    ListingCard(listing: listing)
                }
                .buttonStyle(PressableStyle())
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
    }
}

/// Skeleton cards for the first load.
@MainActor struct ListingGridSkeleton: View {
    var count = 6

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.gutter), GridItem(.flexible(), spacing: Theme.gutter)],
                  spacing: Theme.Space.l) {
            ForEach(0..<count, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Color(uiColor: .systemGray6))
                        .aspectRatio(Theme.photoAspect, contentMode: .fit)
                    SkeletonBlock(width: 120, height: 12)
                    SkeletonBlock(width: 70, height: 12)
                }
            }
        }
        .shimmer()
    }
}
