import Foundation

enum RequestRole: String { case incoming, outgoing }
enum RequestAction: String { case accept, decline, complete, cancel }
enum MyListingsStatus: String { case active, completed }

/// One async function per endpoint in docs/API.md. Every screen goes through this, never URLSession,
/// so `APIConfig.useMocks` switches the whole app between `MockAPIClient` and `LiveAPIClient`.
protocol APIClient: Sendable {
    func health() async throws -> Bool

    // Auth and profile
    func login(email: String) async throws -> LoginResponse
    func me() async throws -> User
    func updateMe(_ update: ProfileUpdate) async throws -> User
    func unread() async throws -> Unread
    func dorms() async throws -> [String]

    // Photos and scan
    func uploadPhoto(_ jpeg: Data, kind: PhotoKind) async throws -> Photo
    func scan(photos: [(jpeg: Data, kind: PhotoKind)], labels: [String]) async throws -> ScanResult
    func meetupSpots() async throws -> [MeetupSpot]

    // Listings
    func listings(_ query: ListingQuery) async throws -> Page<Listing>
    func createListing(_ input: ListingInput) async throws -> Listing
    func listing(id: Int) async throws -> Listing
    func updateListing(id: Int, _ input: ListingInput) async throws -> Listing
    func deleteListing(id: Int) async throws
    func myListings(status: MyListingsStatus) async throws -> Page<Listing>

    // Requests and chat
    func requestListing(id: Int, note: String?) async throws -> ExchangeRequest
    func myRequests(role: RequestRole) async throws -> Page<ExchangeRequest>
    func request(id: Int) async throws -> ExchangeRequest
    func perform(_ action: RequestAction, requestID: Int) async throws -> ExchangeRequest
    func messages(requestID: Int, afterID: Int?) async throws -> [Message]
    func sendMessage(requestID: Int, body: String) async throws -> Message

    // Tier 2
    func myImpact() async throws -> MyImpact
    func campusImpact() async throws -> CampusImpact
    func setSaved(_ saved: Bool, listingID: Int) async throws
    func savedListings() async throws -> Page<Listing>
    func similar(listingID: Int) async throws -> [Listing]
    func styleIdeas(listingID: Int) async throws -> [StyleIdea]
    func leaderboard() async throws -> [LeaderboardEntry]
    func badges() async throws -> [Badge]
    func notifications() async throws -> NotificationPage
    /// `ids == nil` marks every notification read.
    func markNotificationsRead(ids: [Int]?) async throws
    func report(listingID: Int, reason: String?) async throws
}

enum API {
    // Both clients live for the whole run: the mock keeps its in-memory state while you flip to live and back.
    private static let mock = MockAPIClient()
    private static let live = LiveAPIClient()

    /// Chosen on every call from `APIConfig.useMocks`, so the sign-in screen's Mock/Live switch applies immediately.
    static var client: APIClient { APIConfig.useMocks ? mock : live }
}

extension Notification.Name {
    /// Posted when any call returns 401. The session drops the token and goes back to sign-in.
    static let loopUnauthorized = Notification.Name("loopUnauthorized")
}
