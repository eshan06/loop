import Foundation

/// Size options by category (spec §5.4). The same vocabulary drives the feed's size filter,
/// so exact-match filtering on the server stays reliable.
enum SizeVocabulary {
    static let letter = ["XS", "S", "M", "L", "XL", "XXL"]
    static let waist = (24...40).map(String.init)
    static let shoe: [String] = stride(from: 5.0, through: 14.0, by: 0.5).map { value in
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(value)
    }
    static let oneSize = ["One size"]

    static func options(for category: ItemCategory?) -> [String] {
        switch category {
        case .tops, .outerwear, .dresses: letter
        case .bottoms: waist + letter
        case .shoes: shoe
        case .accessories, .bags: oneSize
        case nil: letter
        }
    }

    /// The option matching an AI or user value, ignoring case, or nil if it isn't in the list.
    static func match(_ value: String?, in category: ItemCategory?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return options(for: category).first { $0.caseInsensitiveCompare(value) == .orderedSame }
    }
}
