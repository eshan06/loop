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
        UserDefaults.standard.object(forKey: "useMocks") as? Bool ?? defaultUseMocks
    }

    static let requestTimeout: TimeInterval = 30
    /// `/scan` gives the AI 20 seconds on the server, plus upload time.
    static let scanTimeout: TimeInterval = 45
}
