import Foundation

// Enums from docs/API.md. Raw values are the wire values.

enum ShareType: String, Codable, CaseIterable, Identifiable, Hashable {
    case swap, free, donate
    var id: String { rawValue }
    var label: String {
        switch self {
        case .swap: "Swap"
        case .free: "Free"
        case .donate: "Donate"
        }
    }
}

enum Condition: String, Codable, CaseIterable, Identifiable, Hashable {
    case new, likeNew = "like_new", good, worn
    var id: String { rawValue }
    var label: String {
        switch self {
        case .new: "New"
        case .likeNew: "Like new"
        case .good: "Good"
        case .worn: "Worn"
        }
    }
}

enum ItemCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case tops, bottoms, outerwear, dresses, shoes, accessories, bags
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .tops: "tshirt"
        case .bottoms: "figure.walk"
        case .outerwear: "cloud.drizzle"
        case .dresses: "sparkles"
        case .shoes: "shoeprints.fill"
        case .accessories: "eyeglasses"
        case .bags: "bag"
        }
    }
}

enum ListingStatus: String, Codable, Hashable {
    case active, pending, completed, hidden
}

enum PhotoKind: String, Codable, Hashable {
    case front, back, label, other, avatar
}

enum RequestStatus: String, Codable, Hashable {
    case pending, accepted, declined, completed, cancelled
    var label: String { rawValue.capitalized }
}

enum NotificationType: String, Codable, Hashable {
    case requestReceived = "request_received"
    case requestAccepted = "request_accepted"
    case requestDeclined = "request_declined"
    case newMessage = "new_message"
    case badgeEarned = "badge_earned"

    var symbol: String {
        switch self {
        case .requestReceived: "hand.raised"
        case .requestAccepted: "checkmark.circle"
        case .requestDeclined: "xmark.circle"
        case .newMessage: "bubble.left"
        case .badgeEarned: "rosette"
        }
    }
}

enum ScanSource: String, Codable, Hashable {
    case vision, labels, none
}
