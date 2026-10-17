import Foundation
import UIKit

/// The offline backend used when `APIConfig.useMocks` is on.
///
/// It loads the JSON in `Mocks/` (the shapes from docs/API.md) and keeps state in memory, so the whole
/// demo path works on one phone without a server: posting adds to the feed, requests move through their
/// statuses, chat gets canned replies, and completing an exchange adds impact and can earn a badge.
/// It also plays the other people: the owner accepts your request a few seconds after you send it,
/// replies in chat, and someone requests each item you post.
struct MockAPIClient: APIClient {
    private let backend = MockBackend()

    /// Every mock call waits a little so loading states are visible during development.
    private func delay(_ seconds: Double = 0.3) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    func health() async throws -> Bool { try await delay(); return true }

    func login(email: String) async throws -> LoginResponse { try await delay(); return try await backend.login(email: email) }
    func me() async throws -> User { try await delay(); return try await backend.me() }
    func updateMe(_ update: ProfileUpdate) async throws -> User { try await delay(); return try await backend.updateMe(update) }
    func unread() async throws -> Unread { try await delay(0.1); return try await backend.unread() }
    func dorms() async throws -> [String] { try await delay(); return MockFixtures.dorms }

    func uploadPhoto(_ jpeg: Data, kind: PhotoKind) async throws -> Photo {
        try await delay(0.6)
        return await backend.storePhoto(jpeg, kind: kind)
    }

    func scan(photos: [(jpeg: Data, kind: PhotoKind)], labels: [String]) async throws -> ScanResult {
        try await delay(2.5)
        return await backend.scan(photos: photos)
    }

    func meetupSpots() async throws -> [MeetupSpot] { try await delay(); return MockFixtures.meetupSpots }

    func listings(_ query: ListingQuery) async throws -> Page<Listing> { try await delay(); return try await backend.feed(query) }
    func createListing(_ input: ListingInput) async throws -> Listing { try await delay(0.6); return try await backend.createListing(input) }
    func listing(id: Int) async throws -> Listing { try await delay(); return try await backend.listing(id: id) }
    func updateListing(id: Int, _ input: ListingInput) async throws -> Listing { try await delay(); return try await backend.updateListing(id: id, input) }
    func deleteListing(id: Int) async throws { try await delay(); try await backend.deleteListing(id: id) }
    func myListings(status: MyListingsStatus) async throws -> Page<Listing> { try await delay(); return try await backend.myListings(status: status) }

    func requestListing(id: Int, note: String?) async throws -> ExchangeRequest { try await delay(); return try await backend.requestListing(id: id, note: note) }
    func myRequests(role: RequestRole) async throws -> Page<ExchangeRequest> { try await delay(); return try await backend.myRequests(role: role) }
    func request(id: Int) async throws -> ExchangeRequest { try await delay(0.1); return try await backend.request(id: id) }
    func perform(_ action: RequestAction, requestID: Int) async throws -> ExchangeRequest { try await delay(); return try await backend.perform(action, requestID: requestID) }
    func messages(requestID: Int, afterID: Int?) async throws -> [Message] { try await delay(0.1); return try await backend.messages(requestID: requestID, afterID: afterID) }
    func sendMessage(requestID: Int, body: String) async throws -> Message { try await delay(); return try await backend.sendMessage(requestID: requestID, body: body) }

    func myImpact() async throws -> MyImpact { try await delay(); return try await backend.myImpact() }
    func campusImpact() async throws -> CampusImpact { try await delay(); return await backend.campusImpact }
    func setSaved(_ saved: Bool, listingID: Int) async throws { try await delay(0.2); try await backend.setSaved(saved, listingID: listingID) }
    func savedListings() async throws -> Page<Listing> { try await delay(); return try await backend.savedListings() }
    func similar(listingID: Int) async throws -> [Listing] { try await delay(); return try await backend.similar(listingID: listingID) }

    func styleIdeas(listingID: Int) async throws -> [StyleIdea] {
        try await delay(1.5)
        return MockFixtures.style.ideas
    }

    func leaderboard() async throws -> [LeaderboardEntry] { try await delay(); return await backend.leaderboard() }
    func badges() async throws -> [Badge] { try await delay(); return try await backend.badges() }
    func notifications() async throws -> NotificationPage { try await delay(0.1); return try await backend.notifications() }
    func markNotificationsRead(ids: [Int]?) async throws { try await delay(0.1); try await backend.markRead(ids: ids) }
    func report(listingID: Int, reason: String?) async throws { try await delay(); try await backend.report(listingID: listingID) }
}

// MARK: - Fixtures

enum MockFixtures {
    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("Missing mock \(name).json in the app bundle")
        }
        do {
            return try LiveAPIClient.decoder.decode(T.self, from: data)
        } catch {
            fatalError("Mock \(name).json doesn't match the model: \(error)")
        }
    }

    static let users: [User] = load("users", as: ItemList<User>.self).items
    static let listings: [Listing] = load("listings", as: Page<Listing>.self).items
    static let requests: [ExchangeRequest] = load("requests", as: Page<ExchangeRequest>.self).items
    static let messages: [Message] = load("messages", as: ItemList<Message>.self).items
    static let notifications: NotificationPage = load("notifications")
    static let meetupSpots: [MeetupSpot] = load("meetup_spots", as: ItemList<MeetupSpot>.self).items
    static let dorms: [String] = load("dorms", as: ItemList<String>.self).items
    static let scan: ScanResult = load("scan")
    static let scanNone: ScanResult = load("scan_none")
    static let impactMe: MyImpact = load("impact_me")
    static let impactCampus: CampusImpact = load("impact_campus")
    static let leaderboard: [LeaderboardEntry] = load("leaderboard", as: ItemList<LeaderboardEntry>.self).items
    static let badges: [Badge] = load("badges", as: ItemList<Badge>.self).items
    static let style: StyleResponse = load("style")
}

/// Images for `mock://` photo URLs: photos uploaded in mock mode, keyed by URL.
/// URLs without a stored image get a generated placeholder (see `ImageLoader`).
final class MockMedia: @unchecked Sendable {
    static let shared = MockMedia()
    private var images: [String: UIImage] = [:]
    private let lock = NSLock()

    func store(_ image: UIImage, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        images[url.absoluteString] = image
    }

    func image(for url: URL) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        return images[url.absoluteString]
    }
}

// MARK: - State

actor MockBackend {
    private var users: [Int: User] = [:]
    private var listings: [Int: Listing] = [:]
    private var requests: [Int: ExchangeRequest] = [:]
    private var messages: [Message] = []
    private var notifications: [Int: [AppNotification]] = [:]
    private var saves: [Int: Set<Int>] = [:]
    private var lastRead: [String: Int] = [:]
    private var badgeEarned: [Int: [String: Date]] = [:]
    private var impactBase: [Int: MyImpact] = [:]
    private var createdCount: [Int: Int] = [:]
    private var reports: [Int: Set<Int>] = [:]
    private var leaderboardCounts: [String: Int] = [:]
    private(set) var campusImpact = MockFixtures.impactCampus
    private var nextID = 1000

    init() {
        for user in MockFixtures.users { users[user.id] = user }
        for listing in MockFixtures.listings { listings[listing.id] = listing }
        for request in MockFixtures.requests { requests[request.id] = request }
        messages = MockFixtures.messages
        // The seeded notifications belong to Jordan, the first demo account.
        notifications[3] = MockFixtures.notifications.items
        lastRead["9-3"] = 120
        impactBase[3] = MockFixtures.impactMe
        createdCount[3] = 6
        for entry in MockFixtures.leaderboard { leaderboardCounts[entry.dorm] = entry.itemsShared }
    }

    private func makeID() -> Int { nextID += 1; return nextID }

    // MARK: Session

    private var viewerID: Int {
        get throws {
            guard let token = AuthToken.current, token.hasPrefix("mock-"),
                  let id = Int(token.dropFirst(5)), users[id] != nil else {
                throw unauthorized()
            }
            return id
        }
    }

    private func unauthorized() -> APIError {
        Task { @MainActor in NotificationCenter.default.post(name: .loopUnauthorized, object: nil) }
        return APIError(status: 401, code: "unauthorized", message: "Please sign in again.")
    }

    func login(email: String) throws -> LoginResponse {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard email.contains("@"), email.hasSuffix(".edu") else {
            throw APIError(status: 400, code: "not_edu_email", message: "Use your college .edu email address.")
        }
        if let existing = users.values.first(where: { $0.email == email }) {
            return LoginResponse(token: "mock-\(existing.id)", isNew: false, user: existing)
        }
        let user = User(id: makeID(), name: nil, email: email, campus: Campus(id: 1, name: "Vanderbilt"),
                        dorm: nil, classYear: nil, sizes: Sizes(), avatarUrl: nil, itemsShared: 0, createdAt: .now)
        users[user.id] = user
        return LoginResponse(token: "mock-\(user.id)", isNew: true, user: user)
    }

    func me() throws -> User { try users[viewerID]! }

    func updateMe(_ update: ProfileUpdate) throws -> User {
        let id = try viewerID
        var user = users[id]!
        if let name = update.name { user.name = name }
        if let dorm = update.dorm { user.dorm = dorm }
        if let year = update.classYear { user.classYear = year }
        if let sizes = update.sizes { user.sizes = sizes }
        if let photoID = update.avatarPhotoId { user.avatarUrl = URL(string: "mock://media/avatar-\(photoID).jpg") }
        users[id] = user
        return user
    }

    // MARK: Photos and scan

    func storePhoto(_ jpeg: Data, kind: PhotoKind) -> Photo {
        let id = makeID()
        let url = URL(string: "mock://media/\(kind == .avatar ? "avatar" : "upload")-\(id).jpg")!
        if let image = UIImage(data: jpeg) { MockMedia.shared.store(image, for: url) }
        return Photo(id: id, url: url, kind: kind)
    }

    func scan(photos: [(jpeg: Data, kind: PhotoKind)]) -> ScanResult {
        let stored = photos.map { storePhoto($0.jpeg, kind: $0.kind) }
        let fails = UserDefaults.standard.bool(forKey: "mockScanFails")
        let fixture = fails ? MockFixtures.scanNone : MockFixtures.scan
        return ScanResult(photos: stored, draft: fixture.draft, source: fixture.source)
    }

    // MARK: Listings

    /// A listing as the viewer sees it, with the per-viewer fields filled in.
    private func view(_ listing: Listing, for viewer: Int) -> Listing {
        var listing = listing
        listing.isMine = listing.owner.id == viewer
        listing.savedByMe = saves[viewer, default: []].contains(listing.id)
        let mine = requests.values.filter { $0.listing.id == listing.id && $0.requester.id == viewer }
            .max { $0.createdAt < $1.createdAt }
        listing.myRequestStatus = mine?.status
        listing.myRequestId = mine?.id
        if listing.isMine {
            let onListing = requests.values.filter { $0.listing.id == listing.id }
            listing.pendingRequestCount = onListing.filter { $0.status == .pending }.count
            listing.acceptedRequestId = onListing.first { $0.status == .accepted }?.id
        } else {
            listing.pendingRequestCount = 0
            listing.acceptedRequestId = nil
        }
        return listing
    }

    private func page(_ items: [Listing], viewer: Int) -> Page<Listing> {
        Page(items: items.map { view($0, for: viewer) }, total: items.count, nextOffset: nil)
    }

    func feed(_ query: ListingQuery) throws -> Page<Listing> {
        let viewer = try viewerID
        let q = query.q?.trimmingCharacters(in: .whitespaces).lowercased() ?? ""
        let items = listings.values
            .filter { $0.status == .active }
            .filter { query.shareType == nil || $0.shareType == query.shareType }
            .filter { query.category == nil || $0.category == query.category }
            .filter { query.size == nil || $0.size?.lowercased() == query.size?.lowercased() }
            .filter { listing in
                q.isEmpty || listing.title.lowercased().contains(q) || (listing.brand?.lowercased().contains(q) ?? false)
                    || listing.tags.contains { $0.lowercased().contains(q) }
            }
            .sorted { $0.createdAt > $1.createdAt }
        return page(Array(items.prefix(query.limit)), viewer: viewer)
    }

    func listing(id: Int) throws -> Listing {
        let viewer = try viewerID
        guard let listing = listings[id], listing.status != .hidden || listing.owner.id == viewer else { throw notFound() }
        return view(listing, for: viewer)
    }

    private func notFound() -> APIError { APIError(status: 404, code: "not_found", message: "That item isn't available anymore.") }

    func createListing(_ input: ListingInput) throws -> Listing {
        let viewer = try viewerID
        let photos = input.photoIds.map { id in
            Photo(id: id, url: URL(string: "mock://media/upload-\(id).jpg")!, kind: .front)
        }
        let impact = MockFixtures.listings.first { $0.category == input.category }?.impact ?? .zero
        let listing = Listing(id: makeID(), title: input.title, category: input.category, size: input.size, color: input.color,
                              brand: input.brand, condition: input.condition, description: input.description, tags: input.tags,
                              shareType: input.shareType, status: .active, photos: photos,
                              meetupSpot: MockFixtures.meetupSpots.first { $0.id == input.meetupSpotId },
                              owner: users[viewer]!.asOwner, impact: impact, isMine: true, savedByMe: false,
                              myRequestStatus: nil, myRequestId: nil, pendingRequestCount: 0, acceptedRequestId: nil,
                              createdAt: .now)
        listings[listing.id] = listing
        createdCount[viewer, default: 0] += 1
        checkBadges(for: viewer)
        simulateIncomingRequest(on: listing.id, owner: viewer)
        return view(listing, for: viewer)
    }

    func updateListing(id: Int, _ input: ListingInput) throws -> Listing {
        let viewer = try viewerID
        guard var listing = listings[id] else { throw notFound() }
        guard listing.owner.id == viewer else { throw APIError(status: 403, code: "forbidden", message: "You can only edit your own listings.") }
        guard listing.status != .completed else { throw APIError(status: 409, code: "wrong_status", message: "Completed listings can't be edited.") }
        listing.title = input.title
        listing.category = input.category
        listing.size = input.size
        listing.color = input.color
        listing.brand = input.brand
        listing.condition = input.condition
        listing.description = input.description
        listing.tags = input.tags
        listing.shareType = input.shareType
        listing.meetupSpot = MockFixtures.meetupSpots.first { $0.id == input.meetupSpotId }
        listings[id] = listing
        return view(listing, for: viewer)
    }

    func deleteListing(id: Int) throws {
        let viewer = try viewerID
        guard let listing = listings[id] else { throw notFound() }
        guard listing.owner.id == viewer else { throw APIError(status: 403, code: "forbidden", message: "You can only delete your own listings.") }
        listings[id] = nil
        let gone = requests.values.filter { $0.listing.id == id }.map(\.id)
        for requestID in gone { requests[requestID] = nil }
        messages.removeAll { gone.contains($0.requestId) }
    }

    func myListings(status: MyListingsStatus) throws -> Page<Listing> {
        let viewer = try viewerID
        let items = listings.values
            .filter { $0.owner.id == viewer }
            .filter { status == .completed ? $0.status == .completed : $0.status != .completed }
            .sorted { $0.createdAt > $1.createdAt }
        return page(items, viewer: viewer)
    }

    func setSaved(_ saved: Bool, listingID: Int) throws {
        let viewer = try viewerID
        if saved { saves[viewer, default: []].insert(listingID) } else { saves[viewer, default: []].remove(listingID) }
    }

    func savedListings() throws -> Page<Listing> {
        let viewer = try viewerID
        let items = saves[viewer, default: []].compactMap { listings[$0] }.filter { $0.status != .hidden }
            .sorted { $0.createdAt > $1.createdAt }
        return page(items, viewer: viewer)
    }

    func similar(listingID: Int) throws -> [Listing] {
        let viewer = try viewerID
        guard let base = listings[listingID] else { throw notFound() }
        let tags = Set(base.tags)
        return listings.values
            .filter { $0.id != listingID && $0.status == .active }
            .map { ($0, tags.intersection($0.tags).count * 2 + ($0.category == base.category ? 1 : 0)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(6)
            .map { view($0.0, for: viewer) }
    }

    func report(listingID: Int) throws {
        let viewer = try viewerID
        guard let listing = listings[listingID] else { throw notFound() }
        guard listing.owner.id != viewer else { throw APIError(status: 409, code: "own_listing", message: "You can't report your own listing.") }
        reports[listingID, default: []].insert(viewer)
        if reports[listingID]!.count >= 3 { listings[listingID]?.status = .hidden }
    }

    // MARK: Requests

    private func view(_ request: ExchangeRequest, for viewer: Int) -> ExchangeRequest {
        var request = request
        if let listing = listings[request.listing.id] { request.listing.status = listing.status }
        let other = request.isOwner(viewer) ? request.requester.id : request.owner.id
        let read = lastRead["\(request.id)-\(viewer)"] ?? 0
        request.unreadMessages = messages.filter { $0.requestId == request.id && $0.senderId == other && $0.id > read }.count
        return request
    }

    func requestListing(id: Int, note: String?) throws -> ExchangeRequest {
        let viewer = try viewerID
        guard let listing = listings[id] else { throw notFound() }
        if listing.owner.id == viewer { throw APIError(status: 409, code: "own_listing", message: "That's your own listing.") }
        if listing.status != .active { throw APIError(status: 409, code: "listing_unavailable", message: "This item isn't available anymore.") }
        if requests.values.contains(where: { $0.listing.id == id && $0.requester.id == viewer && [.pending, .accepted].contains($0.status) }) {
            throw APIError(status: 409, code: "already_requested", message: "You've already requested this item.")
        }
        let request = ExchangeRequest(id: makeID(), listing: summary(listing), requester: users[viewer]!.asOwner,
                                      owner: listing.owner, note: note, status: .pending, unreadMessages: 0,
                                      createdAt: .now, updatedAt: .now)
        requests[request.id] = request
        notify(listing.owner.id, .requestReceived, "\(users[viewer]!.asOwner.firstName) requested your \(listing.title)",
               body: note, requestID: request.id, listingID: listing.id)
        simulateOwnerAccepts(request.id)
        return view(request, for: viewer)
    }

    private func summary(_ listing: Listing) -> RequestListing {
        RequestListing(id: listing.id, title: listing.title, photoUrl: listing.coverURL, shareType: listing.shareType, status: listing.status)
    }

    func myRequests(role: RequestRole) throws -> Page<ExchangeRequest> {
        let viewer = try viewerID
        let items = requests.values
            .filter { role == .incoming ? $0.owner.id == viewer : $0.requester.id == viewer }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { view($0, for: viewer) }
        return Page(items: items, total: items.count, nextOffset: nil)
    }

    func request(id: Int) throws -> ExchangeRequest {
        let viewer = try viewerID
        guard let request = requests[id] else { throw notFound() }
        guard request.owner.id == viewer || request.requester.id == viewer else {
            throw APIError(status: 403, code: "forbidden", message: "That request isn't yours.")
        }
        return view(request, for: viewer)
    }

    func perform(_ action: RequestAction, requestID: Int) throws -> ExchangeRequest {
        let viewer = try viewerID
        try apply(action, requestID: requestID, by: viewer)
        return view(requests[requestID]!, for: viewer)
    }

    private func apply(_ action: RequestAction, requestID: Int, by actor: Int) throws {
        guard var request = requests[requestID] else { throw notFound() }
        let wrongStatus = APIError(status: 409, code: "wrong_status", message: "This request can't do that right now.")
        let forbidden = APIError(status: 403, code: "forbidden", message: "Only the other person can do that.")
        switch action {
        case .accept, .decline:
            guard request.owner.id == actor else { throw forbidden }
            guard request.status == .pending else { throw wrongStatus }
            request.status = action == .accept ? .accepted : .declined
            if action == .accept {
                listings[request.listing.id]?.status = .pending
                notify(request.requester.id, .requestAccepted, "\(request.owner.firstName) accepted your request",
                       body: request.listing.title, requestID: request.id, listingID: request.listing.id)
                for other in requests.values where other.listing.id == request.listing.id && other.id != request.id && other.status == .pending {
                    requests[other.id]?.status = .declined
                    requests[other.id]?.updatedAt = .now
                    notify(other.requester.id, .requestDeclined, "\(request.owner.firstName) gave this one to someone else",
                           body: request.listing.title, requestID: other.id, listingID: request.listing.id)
                }
            } else {
                notify(request.requester.id, .requestDeclined, "\(request.owner.firstName) declined your request",
                       body: request.listing.title, requestID: request.id, listingID: request.listing.id)
            }
        case .complete:
            guard request.owner.id == actor || request.requester.id == actor else { throw forbidden }
            guard request.status == .accepted else { throw wrongStatus }
            request.status = .completed
            listings[request.listing.id]?.status = .completed
            if let listing = listings[request.listing.id] {
                for person in [request.owner.id, request.requester.id] {
                    var base = impactBase[person] ?? MyImpact(itemsShared: 0, itemsReceived: 0, textileKg: 0, waterL: 0, co2Kg: 0)
                    base.textileKg += listing.impact.textileKg
                    base.waterL += listing.impact.waterL
                    base.co2Kg += listing.impact.co2Kg
                    if person == request.owner.id { base.itemsShared += 1 } else { base.itemsReceived += 1 }
                    impactBase[person] = base
                }
                campusImpact.itemsRehomed += 1
                campusImpact.textileKg += listing.impact.textileKg
                campusImpact.waterL += listing.impact.waterL
                campusImpact.co2Kg += listing.impact.co2Kg
                if let dorm = users[request.owner.id]?.dorm ?? listing.owner.dorm {
                    leaderboardCounts[dorm, default: 0] += 1
                }
                users[request.owner.id]?.itemsShared += 1
            }
            checkBadges(for: request.owner.id)
            checkBadges(for: request.requester.id)
        case .cancel:
            guard request.requester.id == actor else { throw forbidden }
            guard [.pending, .accepted].contains(request.status) else { throw wrongStatus }
            if request.status == .accepted { listings[request.listing.id]?.status = .active }
            request.status = .cancelled
        }
        request.updatedAt = .now
        if let listing = listings[request.listing.id] { request.listing.status = listing.status }
        requests[requestID] = request
    }

    // MARK: Messages

    func messages(requestID: Int, afterID: Int?) throws -> [Message] {
        let viewer = try viewerID
        _ = try self.request(id: requestID)
        let items = messages.filter { $0.requestId == requestID && $0.id > (afterID ?? 0) }
        if let last = items.last { lastRead["\(requestID)-\(viewer)"] = max(lastRead["\(requestID)-\(viewer)"] ?? 0, last.id) }
        return items
    }

    func sendMessage(requestID: Int, body: String) throws -> Message {
        let viewer = try viewerID
        let request = try self.request(id: requestID)
        guard request.status == .accepted else {
            throw APIError(status: 409, code: "wrong_status", message: "You can message once the request is accepted.")
        }
        let message = post(body, requestID: requestID, from: viewer)
        simulateReply(requestID: requestID, to: viewer)
        return message
    }

    @discardableResult
    private func post(_ body: String, requestID: Int, from sender: Int) -> Message {
        let message = Message(id: makeID(), requestId: requestID, senderId: sender, body: body, createdAt: .now)
        messages.append(message)
        lastRead["\(requestID)-\(sender)"] = message.id
        if let request = requests[requestID] {
            let recipient = request.owner.id == sender ? request.requester : request.owner
            let senderName = (request.owner.id == sender ? request.owner : request.requester).firstName
            notify(recipient.id, .newMessage, "\(senderName) sent you a message", body: body,
                   requestID: requestID, listingID: request.listing.id)
            requests[requestID]?.updatedAt = .now
        }
        return message
    }

    // MARK: Impact, badges, leaderboard

    func myImpact() throws -> MyImpact {
        let viewer = try viewerID
        return impactBase[viewer] ?? MyImpact(itemsShared: 0, itemsReceived: 0, textileKg: 0, waterL: 0, co2Kg: 0)
    }

    func leaderboard() -> [LeaderboardEntry] {
        let sorted = leaderboardCounts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
        var entries: [LeaderboardEntry] = []
        for (index, item) in sorted.enumerated() {
            let rank = index > 0 && sorted[index - 1].value == item.value ? entries[index - 1].rank : index + 1
            entries.append(LeaderboardEntry(rank: rank, dorm: item.key, itemsShared: item.value))
        }
        return entries
    }

    private func badgeProgress(for user: Int) -> [Badge] {
        let completed = requests.values.filter { $0.status == .completed && ($0.owner.id == user || $0.requester.id == user) }.count
        let donated = requests.values.filter { request in
            request.status == .completed && request.owner.id == user && request.listing.shareType == .donate
        }.count + (user == 3 ? 3 : 0)
        let created = createdCount[user, default: 0]
        let progress = ["first_swap": completed, "giving_back": donated, "closet_cleanout": created]
        return MockFixtures.badges.map { badge in
            var badge = badge
            badge.progress = min(progress[badge.id] ?? 0, badge.goal)
            badge.earnedAt = badgeEarned[user]?[badge.id]
            return badge
        }
    }

    private func checkBadges(for user: Int) {
        for badge in badgeProgress(for: user) where badge.progress >= badge.goal && badge.earnedAt == nil {
            badgeEarned[user, default: [:]][badge.id] = .now
            notify(user, .badgeEarned, "You earned \(badge.name)", body: badge.description, requestID: nil, listingID: nil)
        }
    }

    func badges() throws -> [Badge] { badgeProgress(for: try viewerID) }

    // MARK: Notifications

    private func notify(_ user: Int, _ type: NotificationType, _ title: String, body: String?, requestID: Int?, listingID: Int?) {
        let notification = AppNotification(id: makeID(), type: type, title: title, body: body, requestId: requestID,
                                           listingId: listingID, read: false, createdAt: .now)
        notifications[user, default: []].insert(notification, at: 0)
    }

    func notifications() throws -> NotificationPage {
        let items = notifications[try viewerID, default: []]
        return NotificationPage(items: Array(items.prefix(20)), total: items.count, nextOffset: nil,
                                unread: items.filter { !$0.read }.count)
    }

    func markRead(ids: [Int]?) throws {
        let viewer = try viewerID
        notifications[viewer] = notifications[viewer, default: []].map { notification in
            var notification = notification
            if ids == nil || ids!.contains(notification.id) { notification.read = true }
            return notification
        }
    }

    func unread() throws -> Unread {
        let viewer = try viewerID
        let mine = requests.values.filter { $0.owner.id == viewer || $0.requester.id == viewer }.map { view($0, for: viewer) }
        return Unread(notifications: notifications[viewer, default: []].filter { !$0.read }.count,
                      messages: mine.reduce(0) { $0 + $1.unreadMessages },
                      incomingRequests: mine.filter { $0.owner.id == viewer && $0.status == .pending }.count)
    }

    // MARK: Simulated other people

    private func simulateOwnerAccepts(_ requestID: Int) {
        Task {
            try? await Task.sleep(for: .seconds(4))
            await self.ownerAccepts(requestID)
        }
    }

    private func ownerAccepts(_ requestID: Int) {
        guard let request = requests[requestID], request.status == .pending else { return }
        try? apply(.accept, requestID: requestID, by: request.owner.id)
        Task {
            try? await Task.sleep(for: .seconds(3))
            await self.post("Hey! Happy to meet up. When works for you?", requestID: requestID, from: request.owner.id)
        }
    }

    private static let replies = ["Sounds good!", "Perfect, see you then.", "I'll bring it in a tote bag.", "On my way 👋"]
    private var replyIndex = 0

    private func simulateReply(requestID: Int, to viewer: Int) {
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            await self.reply(requestID: requestID, to: viewer)
        }
    }

    private func reply(requestID: Int, to viewer: Int) {
        guard let request = requests[requestID], request.status == .accepted else { return }
        let other = request.owner.id == viewer ? request.requester.id : request.owner.id
        let reply = Self.replies[replyIndex % Self.replies.count]
        replyIndex += 1
        post(reply, requestID: requestID, from: other)
    }

    private func simulateIncomingRequest(on listingID: Int, owner: Int) {
        Task {
            try? await Task.sleep(for: .seconds(8))
            await self.someoneRequests(listingID, owner: owner)
        }
    }

    private func someoneRequests(_ listingID: Int, owner: Int) {
        guard let listing = listings[listingID], listing.status == .active,
              let requester = users.values.filter({ $0.id != owner && $0.name != nil }).min(by: { $0.id < $1.id }) else { return }
        let request = ExchangeRequest(id: makeID(), listing: summary(listing), requester: requester.asOwner,
                                      owner: listing.owner, note: "Is this still available? I'd love it!", status: .pending,
                                      unreadMessages: 0, createdAt: .now, updatedAt: .now)
        requests[request.id] = request
        notify(owner, .requestReceived, "\(requester.asOwner.firstName) requested your \(listing.title)",
               body: request.note, requestID: request.id, listingID: listingID)
    }
}
