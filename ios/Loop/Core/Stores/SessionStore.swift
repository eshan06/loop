import SwiftUI

/// Who is signed in. The token lives in the Keychain (`AuthToken`); the user comes from `GET /me`.
@Observable @MainActor
final class SessionStore {
    enum Phase: Equatable {
        case launching, signedOut, needsSetup, signedIn
    }

    private(set) var phase: Phase = .launching
    private(set) var user: User?

    var userID: Int? { user?.id }

    init() {
        NotificationCenter.default.addObserver(forName: .loopUnauthorized, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.signOut() }
        }
    }

    /// On launch: with a saved token, load the user; any 401 sends us back to sign-in.
    func restore() async {
        guard AuthToken.current != nil else { phase = .signedOut; return }
        do {
            let user = try await API.client.me()
            apply(user)
        } catch {
            // Offline with a saved token: stay signed out only if the token was rejected.
            if (error as? APIError)?.status == 401 { signOut() } else { phase = .signedOut }
        }
    }

    func signIn(email: String) async throws {
        let response = try await API.client.login(email: email)
        AuthToken.set(response.token)
        if response.isNew {
            user = response.user
            phase = .needsSetup
        } else {
            apply(response.user)
        }
    }

    /// The server's note (S-8): someone who quit during setup comes back with `name == nil`, so
    /// setup shows whenever the name is missing, not only when `is_new` is true.
    private func apply(_ user: User) {
        self.user = user
        phase = user.name == nil ? .needsSetup : .signedIn
    }

    func update(_ user: User) {
        self.user = user
        if phase == .needsSetup, user.name != nil { phase = .signedIn }
    }

    func refresh() async {
        if let user = try? await API.client.me() { self.user = user }
    }

    func signOut() {
        AuthToken.set(nil)
        user = nil
        phase = .signedOut
    }
}
