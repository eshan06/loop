import SwiftUI

@Observable @MainActor
final class ReviewModel {
    enum ScanState: Equatable {
        case loading
        case filled(ScanSource)
        /// The AI couldn't fill it in (`source: none`), or the request failed.
        case failed
    }

    let shots: [(kind: PhotoKind, image: UIImage)]
    var form = ListingFormState()
    private(set) var scanState: ScanState = .loading
    private(set) var photoIDs: [Int]?
    private(set) var spots: [MeetupSpot]?
    private(set) var isPosting = false
    var postError: String?

    private let labels: () async -> [String]

    init(shots: [(kind: PhotoKind, image: UIImage)], labels: @escaping () async -> [String]) {
        self.shots = shots
        self.labels = labels
    }

    var isLocked: Bool { scanState == .loading }

    func loadSpots() async {
        guard spots == nil else { return }
        if let spots = try? await API.client.meetupSpots() {
            self.spots = spots
            if spots.count == 1 { form.meetupSpotID = spots[0].id }
        }
    }

    func runScan() async {
        withAnimation(.smooth) { scanState = .loading }
        let jpegs = shots.map { (jpeg: ImageProcessing.jpeg($0.image), kind: $0.kind) }
        let labels = await labels()
        do {
            let result = try await API.client.scan(photos: jpegs, labels: labels)
            photoIDs = result.photos.map(\.id)
            withAnimation(.smooth(duration: 0.35)) {
                if result.source == .none {
                    scanState = .failed
                } else {
                    form.apply(result.draft)
                    scanState = .filled(result.source)
                }
            }
        } catch {
            guard !error.isCancellation else { return }
            withAnimation(.smooth) { scanState = .failed }
        }
    }

    func post() async -> Listing? {
        isPosting = true
        postError = nil
        defer { isPosting = false }
        do {
            // If /scan itself failed there are no saved photos yet, so upload them now.
            var ids = photoIDs
            if ids == nil {
                var uploaded: [Int] = []
                for shot in shots {
                    uploaded.append(try await API.client.uploadPhoto(ImageProcessing.jpeg(shot.image), kind: shot.kind).id)
                }
                photoIDs = uploaded
                ids = uploaded
            }
            guard let input = form.input(photoIDs: ids ?? []) else { return nil }
            return try await API.client.createListing(input)
        } catch {
            postError = error.userMessage
            return nil
        }
    }
}

/// The AI-filled draft. Opens right away; the AI fields are skeletons until the scan returns.
struct ReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Router.self) private var router
    @Environment(ListingCache.self) private var cache

    @State private var model: ReviewModel

    init(shots: [(kind: PhotoKind, image: UIImage)], labels: @escaping () async -> [String]) {
        _model = State(initialValue: ReviewModel(shots: shots, labels: labels))
    }

    var body: some View {
        Form {
            Section {
                photoRow.listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section { banner }
            ShareFields(form: $model.form, spots: model.spots)
            ListingDetailsFields(form: $model.form, locked: model.isLocked)
            if let error = model.postError {
                Section { Text(error).foregroundStyle(Theme.destructive) }
            }
        }
        .animation(.smooth, value: model.isLocked)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            PrimaryButton(title: "Post", isLoading: model.isPosting, isEnabled: model.form.isValid && !model.isLocked, action: post)
                .padding(.horizontal, Theme.margin)
                .padding(.top, Theme.Space.s)
                .padding(.bottom, Theme.Space.xs)
                .background(.bar)
        }
        .task {
            async let spots: () = model.loadSpots()
            async let scan: () = model.runScan()
            _ = await (spots, scan)
        }
        .sensoryFeedback(.warning, trigger: model.scanState) { _, new in new == .failed }
    }

    private var photoRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(Array(model.shots.enumerated()), id: \.offset) { _, shot in
                    Image(uiImage: shot.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 112, height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .overlay(alignment: .bottomLeading) {
                            TagCapsule(text: shot.kind.stepTitle).padding(6)
                        }
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var banner: some View {
        switch model.scanState {
        case .loading:
            HStack(spacing: Theme.Space.s) {
                ProgressView()
                Text("Reading your photos…").font(.subheadline.weight(.medium))
            }
            .shimmer()
        case .filled:
            Label("Filled in by AI. Check before posting.", systemImage: "sparkles")
                .font(.subheadline.weight(.medium))
        case .failed:
            HStack {
                Label("Couldn't fill this in automatically.", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Button("Try again") { Task { await model.runScan() } }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
            }
        }
    }

    private func post() {
        Task {
            guard let listing = await model.post() else { return }
            cache.upsert(listing)
            router.tab = .feed
            router.popToRoot(.feed)
            router.isScanPresented = false
            try? await Task.sleep(for: .milliseconds(450))
            router.justPostedListingID = listing.id
        }
    }
}
