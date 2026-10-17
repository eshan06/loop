import Foundation

/// The one switch between mock data and the real backend.
///
/// `useMocks` defaults to `defaultUseMocks`, and a launch argument overrides it for a single run
/// without editing code: `-useMocks NO` (or `YES`) in the scheme, or
/// `xcrun simctl launch booted com.stacked.loop -useMocks NO`.
enum APIConfig {
    static let defaultUseMocks = true

    /// The live server, from "Server status" in `coord/server.md`.
    static let baseURL = URL(string: "http://163.192.218.131:8000")!

    static var useMocks: Bool {
        // A launch argument arrives as a string ("NO"), so read it with `bool(forKey:)`, not a Bool cast.
        guard UserDefaults.standard.object(forKey: "useMocks") != nil else { return defaultUseMocks }
        return UserDefaults.standard.bool(forKey: "useMocks")
    }

    static let requestTimeout: TimeInterval = 30
    /// `/scan` gives the AI 20 seconds on the server, plus upload time.
    static let scanTimeout: TimeInterval = 45
}
