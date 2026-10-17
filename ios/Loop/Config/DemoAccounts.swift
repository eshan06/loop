import Foundation

/// Quick-login accounts on the sign-in screen, shown in DEBUG builds only.
/// The server lane seeds these (S-15); the emails are agreed in coord/ios.md (IOS-1).
enum DemoAccounts {
    static let all: [(label: String, email: String)] = [
        ("Jordan", "jordan.park@vanderbilt.edu"),
        ("Sam", "sam.lee@vanderbilt.edu"),
        ("Riley", "riley.chen@vanderbilt.edu"),
    ]
}
