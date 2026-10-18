import Foundation

/// The one switch between mock data and the real backend.
///
/// `useMocks` defaults to `defaultUseMocks`, and a launch argument overrides it for a single run
/// without editing code: `-useMocks NO` (or `YES`) in the scheme, or
/// `xcrun simctl launch booted com.stacked.loop -useMocks NO`.
enum APIConfig {
    /// Debug builds start on mocks (the sign-in screen can switch); Release (TestFlight) has no switch, so it uses the live server.
    #if DEBUG
    static let defaultUseMocks = true
    #else
    static let defaultUseMocks = false
    #endif

    /// The live server, from "Server status" in `coord/server.md`.
    static let baseURL = URL(string: "http://163.192.218.131:8000")!

    static var useMocks: Bool {
        // A launch argument arrives as a string ("NO"), so read it with `bool(forKey:)`, not a Bool cast.
        guard UserDefaults.standard.object(forKey: "useMocks") != nil else { return defaultUseMocks }
        return UserDefaults.standard.bool(forKey: "useMocks")
    }

    /// Persist the Mock/Live choice (the sign-in screen's switch). A launch argument still wins.
    static func setUseMocks(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "useMocks")
    }

    static let requestTimeout: TimeInterval = 30
    /// `/scan` gives the AI 20 seconds on the server, plus upload time.
    static let scanTimeout: TimeInterval = 45
}
