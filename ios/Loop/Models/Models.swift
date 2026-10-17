import Foundation

// Codable models for every object in docs/API.md (contract v1).
// Decoded with `.convertFromSnakeCase` and `.iso8601`, so `avatar_url` is `avatarUrl`, and so on.

struct Campus: Codable, Hashable {
    let id: Int
    let name: String
}

struct Sizes: Codable, Hashable {
    var top: String?
    var bottom: String?
    var shoe: String?

    // PATCH /me replaces all three sizes, so send explicit nulls instead of leaving keys out.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(top, forKey: .top)
        try container.encode(bottom, forKey: .bottom)
        try container.encode(shoe, forKey: .shoe)
    }
}

struct User: Codable, Hashable, Identifiable {
    let id: Int
    var name: String?
    let email: String
    let campus: Campus
    var dorm: String?
    var classYear: Int?
    var sizes: Sizes
    var avatarUrl: URL?
    var itemsShared: Int
    let createdAt: Date

    var asOwner: Owner {
        Owner(id: id, name: name, dorm: dorm, avatarUrl: avatarUrl, itemsShared: itemsShared)
    }
}

/// Another person, as they appear on listings and requests.
struct Owner: Codable, Hashable, Identifiable {
    let id: Int
    var name: String?
    var dorm: String?
    var avatarUrl: URL?
    var itemsShared: Int

    var displayName: String { name ?? "Loop member" }
    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? displayName }
}

struct Photo: Codable, Hashable, Identifiable {
    let id: Int
    let url: URL
    let kind: PhotoKind
}

struct MeetupSpot: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
}

struct Impact: Codable, Hashable {
    var textileKg: Double
    var waterL: Double
    var co2Kg: Double

    static let zero = Impact(textileKg: 0, waterL: 0, co2Kg: 0)
}

struct Listing: Codable, Hashable, Identifiable {
    let id: Int
    var title: String
    var category: ItemCategory
    var size: String?
    var color: String?
    var brand: String?
    var condition: Condition
    var description: String?
    var tags: [String]
    var shareType: ShareType
    var status: ListingStatus
    var photos: [Photo]
    var meetupSpot: MeetupSpot?
    var owner: Owner
    var impact: Impact
    var isMine: Bool
    var savedByMe: Bool
    var myRequestStatus: RequestStatus?
    var myRequestId: Int?
    var pendingRequestCount: Int
    var acceptedRequestId: Int?
    let createdAt: Date

    var coverURL: URL? { photos.first?.url }
}

struct ScanDraft: Codable, Hashable {
    var title: String?
    var category: ItemCategory?
    var size: String?
    var color: String?
    var brand: String?
    var condition: Condition?
    var description: String?
    var tags: [String]

    static let empty = ScanDraft(tags: [])
}

struct ScanResult: Codable, Hashable {
    let photos: [Photo]
    let draft: ScanDraft
    let source: ScanSource
}

/// The short listing summary inside a Request.
struct RequestListing: Codable, Hashable {
    let id: Int
    var title: String
    var photoUrl: URL?
    var shareType: ShareType
    var status: ListingStatus
}

/// A request for an item. Named `ExchangeRequest` so it doesn't read like a network request.
struct ExchangeRequest: Codable, Hashable, Identifiable {
    let id: Int
    var listing: RequestListing
    var requester: Owner
    var owner: Owner
    var note: String?
    var status: RequestStatus
    var unreadMessages: Int
    let createdAt: Date
    var updatedAt: Date

    func isOwner(_ userID: Int?) -> Bool { owner.id == userID }
    func otherPerson(for userID: Int?) -> Owner { isOwner(userID) ? requester : owner }
}

struct Message: Codable, Hashable, Identifiable {
    let id: Int
    let requestId: Int
    let senderId: Int
    let body: String
    let createdAt: Date
}

struct AppNotification: Codable, Hashable, Identifiable {
    let id: Int
    let type: NotificationType
    let title: String
    let body: String?
    let requestId: Int?
    let listingId: Int?
    var read: Bool
    let createdAt: Date
}

struct Unread: Codable, Hashable {
    var notifications: Int
    var messages: Int
    var incomingRequests: Int

    var requestsBadge: Int { messages + incomingRequests }
    static let zero = Unread(notifications: 0, messages: 0, incomingRequests: 0)
}

struct MyImpact: Codable, Hashable {
    var itemsShared: Int
    var itemsReceived: Int
    var textileKg: Double
    var waterL: Double
    var co2Kg: Double

    var impact: Impact { Impact(textileKg: textileKg, waterL: waterL, co2Kg: co2Kg) }
}

struct CampusImpact: Codable, Hashable {
    var itemsRehomed: Int
    var textileKg: Double
    var waterL: Double
    var co2Kg: Double
    var topDorm: String?
}

struct LeaderboardEntry: Codable, Hashable {
    let rank: Int
    let dorm: String
    let itemsShared: Int
}

struct Badge: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let description: String
    var earnedAt: Date?
    var progress: Int
    var goal: Int

    var isEarned: Bool { earnedAt != nil }
    var symbol: String {
        switch id {
        case "first_swap": "arrow.2.squarepath"
        case "giving_back": "heart"
        case "closet_cleanout": "hanger"
        default: "rosette"
        }
    }
}

struct StyleIdea: Codable, Hashable {
    let title: String
    let description: String
}

// MARK: - Response wrappers

/// A paged list: `{"items": [...], "total": 87, "next_offset": 20}`.
struct Page<T: Codable & Hashable>: Codable, Hashable {
    var items: [T]
    var total: Int
    var nextOffset: Int?
}

/// An unpaged list: `{"items": [...]}`.
struct ItemList<T: Codable & Hashable>: Codable, Hashable {
    var items: [T]
}

struct NotificationPage: Codable, Hashable {
    var items: [AppNotification]
    var total: Int
    var nextOffset: Int?
    var unread: Int
}

struct LoginResponse: Codable {
    let token: String
    let isNew: Bool
    let user: User
}

struct StyleResponse: Codable {
    let ideas: [StyleIdea]
}

// MARK: - Request bodies (encoded with `.convertToSnakeCase`)

struct ProfileUpdate: Encodable {
    var name: String?
    var dorm: String?
    var classYear: Int?
    var sizes: Sizes?
    var avatarPhotoId: Int?
}

struct ListingInput: Encodable, Hashable {
    var title: String
    var category: ItemCategory
    var size: String?
    var color: String?
    var brand: String?
    var condition: Condition
    var description: String?
    var tags: [String]
    var shareType: ShareType
    var meetupSpotId: Int
    var photoIds: [Int]
}

struct ListingQuery: Hashable {
    var shareType: ShareType?
    var category: ItemCategory?
    var size: String?
    var q: String?
    var limit = 50
    var offset = 0

    var isFiltered: Bool { category != nil || size != nil || !(q ?? "").isEmpty }
}
