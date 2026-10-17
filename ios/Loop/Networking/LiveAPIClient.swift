import Foundation

/// Talks to the real backend at `APIConfig.baseURL`.
struct LiveAPIClient: APIClient {
    private let baseURL = APIConfig.baseURL
    private let session: URLSession = .shared

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Endpoints

    func health() async throws -> Bool {
        struct Health: Decodable { let status: String }
        let result: Health = try await send("GET", "/health")
        return result.status == "ok"
    }

    func login(email: String) async throws -> LoginResponse {
        try await send("POST", "/auth/login", body: ["email": email])
    }

    func me() async throws -> User { try await send("GET", "/me") }

    func updateMe(_ update: ProfileUpdate) async throws -> User {
        try await send("PATCH", "/me", body: update)
    }

    func unread() async throws -> Unread { try await send("GET", "/me/unread") }

    func dorms() async throws -> [String] {
        let list: ItemList<String> = try await send("GET", "/dorms")
        return list.items
    }

    func uploadPhoto(_ jpeg: Data, kind: PhotoKind) async throws -> Photo {
        var form = MultipartForm()
        form.addField("kind", kind.rawValue)
        form.addFile("file", filename: "photo.jpg", data: jpeg)
        return try await send("POST", "/photos", multipart: form)
    }

    func scan(photos: [(jpeg: Data, kind: PhotoKind)], labels: [String]) async throws -> ScanResult {
        try await send("POST", "/scan", multipart: Self.scanForm(photos: photos, labels: labels), timeout: APIConfig.scanTimeout)
    }

    /// The `POST /scan` body from docs/API.md: one `photos` part per JPEG in order front, back, label,
    /// `kinds` with one kind per photo, and the optional on-device `labels`.
    static func scanForm(photos: [(jpeg: Data, kind: PhotoKind)], labels: [String]) -> MultipartForm {
        var form = MultipartForm()
        for (index, photo) in photos.enumerated() {
            form.addFile("photos", filename: "photo\(index).jpg", data: photo.jpeg)
        }
        form.addField("kinds", photos.map(\.kind.rawValue).joined(separator: ","))
        if !labels.isEmpty {
            form.addField("labels", labels.joined(separator: ","))
        }
        return form
    }

    func meetupSpots() async throws -> [MeetupSpot] {
        let list: ItemList<MeetupSpot> = try await send("GET", "/meetup-spots")
        return list.items
    }

    func listings(_ query: ListingQuery) async throws -> Page<Listing> {
        var items = [URLQueryItem(name: "limit", value: String(query.limit)),
                     URLQueryItem(name: "offset", value: String(query.offset))]
        if let shareType = query.shareType { items.append(.init(name: "share_type", value: shareType.rawValue)) }
        if let category = query.category { items.append(.init(name: "category", value: category.rawValue)) }
        if let size = query.size, !size.isEmpty { items.append(.init(name: "size", value: size)) }
        if let q = query.q?.trimmingCharacters(in: .whitespaces), !q.isEmpty { items.append(.init(name: "q", value: q)) }
        return try await send("GET", "/listings", query: items)
    }

    func createListing(_ input: ListingInput) async throws -> Listing {
        try await send("POST", "/listings", body: input)
    }

    func listing(id: Int) async throws -> Listing { try await send("GET", "/listings/\(id)") }

    func updateListing(id: Int, _ input: ListingInput) async throws -> Listing {
        try await send("PATCH", "/listings/\(id)", body: input)
    }

    func deleteListing(id: Int) async throws {
        try await sendEmpty("DELETE", "/listings/\(id)")
    }

    func myListings(status: MyListingsStatus) async throws -> Page<Listing> {
        try await send("GET", "/me/listings", query: [.init(name: "status", value: status.rawValue),
                                                       .init(name: "limit", value: "50")])
    }

    func requestListing(id: Int, note: String?) async throws -> ExchangeRequest {
        struct Body: Encodable { let note: String? }
        return try await send("POST", "/listings/\(id)/requests", body: Body(note: note))
    }

    func myRequests(role: RequestRole) async throws -> Page<ExchangeRequest> {
        try await send("GET", "/me/requests", query: [.init(name: "role", value: role.rawValue),
                                                       .init(name: "limit", value: "50")])
    }

    func request(id: Int) async throws -> ExchangeRequest { try await send("GET", "/requests/\(id)") }

    func perform(_ action: RequestAction, requestID: Int) async throws -> ExchangeRequest {
        try await send("POST", "/requests/\(requestID)/\(action.rawValue)")
    }

    func messages(requestID: Int, afterID: Int?) async throws -> [Message] {
        let query = afterID.map { [URLQueryItem(name: "after_id", value: String($0))] } ?? []
        let list: ItemList<Message> = try await send("GET", "/requests/\(requestID)/messages", query: query)
        return list.items
    }

    func sendMessage(requestID: Int, body: String) async throws -> Message {
        try await send("POST", "/requests/\(requestID)/messages", body: ["body": body])
    }

    func myImpact() async throws -> MyImpact { try await send("GET", "/impact/me") }

    func campusImpact() async throws -> CampusImpact { try await send("GET", "/impact/campus") }

    func setSaved(_ saved: Bool, listingID: Int) async throws {
        try await sendEmpty(saved ? "PUT" : "DELETE", "/listings/\(listingID)/save")
    }

    func savedListings() async throws -> Page<Listing> {
        try await send("GET", "/me/saved", query: [.init(name: "limit", value: "50")])
    }

    func similar(listingID: Int) async throws -> [Listing] {
        let list: ItemList<Listing> = try await send("GET", "/listings/\(listingID)/similar")
        return list.items
    }

    func styleIdeas(listingID: Int) async throws -> [StyleIdea] {
        let response: StyleResponse = try await send("POST", "/listings/\(listingID)/style", timeout: APIConfig.scanTimeout)
        return response.ideas
    }

    func leaderboard() async throws -> [LeaderboardEntry] {
        let list: ItemList<LeaderboardEntry> = try await send("GET", "/leaderboard/dorms")
        return list.items
    }

    func badges() async throws -> [Badge] {
        let list: ItemList<Badge> = try await send("GET", "/me/badges")
        return list.items
    }

    func notifications() async throws -> NotificationPage {
        try await send("GET", "/notifications", query: [.init(name: "limit", value: "20")])
    }

    func markNotificationsRead(ids: [Int]?) async throws {
        struct Body: Encodable { var ids: [Int]?; var all: Bool? }
        try await sendEmpty("POST", "/notifications/read", body: ids.map { Body(ids: $0) } ?? Body(all: true))
    }

    func report(listingID: Int, reason: String?) async throws {
        struct Body: Encodable { let reason: String? }
        try await sendEmpty("POST", "/listings/\(listingID)/report", body: Body(reason: reason))
    }

    // MARK: - Plumbing

    private func send<T: Decodable>(_ method: String, _ path: String, query: [URLQueryItem] = [],
                                    body: (any Encodable)? = nil, multipart: MultipartForm? = nil,
                                    timeout: TimeInterval = APIConfig.requestTimeout) async throws -> T {
        let data = try await perform(method, path, query: query, body: body, multipart: multipart, timeout: timeout)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(T.self) from \(method) \(path) failed: \(error)")
            #endif
            throw APIError.decoding
        }
    }

    private func sendEmpty(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await perform(method, path, query: [], body: body, multipart: nil, timeout: APIConfig.requestTimeout)
    }

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], body: (any Encodable)?,
                         multipart: MultipartForm?, timeout: TimeInterval) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = AuthToken.current {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let multipart {
            request.setValue(multipart.contentType, forHTTPHeaderField: "Content-Type")
            request.httpBody = multipart.finalized()
        } else if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try Self.encoder.encode(body)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if error.isCancellation { throw CancellationError() }
            throw APIError.network
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if status == 401 {
                await MainActor.run { NotificationCenter.default.post(name: .loopUnauthorized, object: nil) }
            }
            if let envelope = try? Self.decoder.decode(ErrorEnvelope.self, from: data) {
                throw APIError(status: status, code: envelope.error.code, message: envelope.error.message)
            }
            throw APIError.generic(status: status)
        }
        return data
    }
}

/// A `multipart/form-data` body.
struct MultipartForm {
    private let boundary = "loop-\(UUID().uuidString)"
    private var body = Data()

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, data: Data, mimeType: String = "image/jpeg") {
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        body.append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        body.append("\r\n")
    }

    func finalized() -> Data {
        var data = body
        data.append("--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}
