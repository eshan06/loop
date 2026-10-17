import Foundation

/// The error shape from docs/API.md: `{"error": {"code": "...", "message": "..."}}`.
/// `message` is written for users, so screens show it as is.
struct APIError: Error, LocalizedError, Hashable {
    let status: Int
    let code: String
    let message: String

    var errorDescription: String? { message }

    static let network = APIError(status: 0, code: "network", message: "Can't reach Loop right now. Check your connection and try again.")
    static let decoding = APIError(status: 0, code: "decoding", message: "Something went wrong reading the server's reply.")

    static func generic(status: Int) -> APIError {
        APIError(status: status, code: "server_error", message: "Something went wrong. Try again.")
    }
}

extension Error {
    /// A message to show the user for any error.
    var userMessage: String {
        (self as? APIError)?.message ?? (self as? LocalizedError)?.errorDescription ?? APIError.network.message
    }

    var apiCode: String? { (self as? APIError)?.code }
    var isCancellation: Bool { self is CancellationError || (self as? URLError)?.code == .cancelled }
}

struct ErrorEnvelope: Decodable {
    struct Body: Decodable {
        let code: String
        let message: String
    }
    let error: Body
}
