import SwiftUI

/// One request and its chat. Polls every 3 seconds while visible:
/// new messages with `after_id`, and `GET /requests/{id}` for live status changes.
@Observable @MainActor
final class ThreadModel {
    struct Outgoing: Identifiable, Equatable {
        let id = UUID()
        let body: String
        var failed = false
    }

    struct Celebration: Identifiable, Equatable {
        let id = UUID()
        let impact: Impact
        let newBadges: [Badge]
    }

    let requestID: Int
    private(set) var request: ExchangeRequest?
    private(set) var messages: [Message] = []
    private(set) var outgoing: [Outgoing] = []
    private(set) var error: String?
    private(set) var isWorking = false
    var celebration: Celebration?

    private var badgeSnapshot: [Badge]?
    private var completedHere = false
    private var pollTask: Task<Void, Never>?

    init(requestID: Int) {
        self.requestID = requestID
    }

    var lastMessageID: Int? { messages.last?.id }

    func start(onChange: @escaping () -> Void) {
        guard pollTask == nil else { return }
        pollTask = Task {
            await loadInitial()
            onChange()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { break }
                if await poll() { onChange() }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func loadInitial() async {
        do {
            async let requestResult = API.client.request(id: requestID)
            async let messagesResult = API.client.messages(requestID: requestID, afterID: nil)
            let (request, messages) = try await (requestResult, messagesResult)
            self.request = request
            self.messages = messages
            error = nil
            if request.status == .accepted { badgeSnapshot = try? await API.client.badges() }
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
    }

    /// Returns true when something new arrived.
    private func poll() async -> Bool {
        var changed = false
        if let fresh = try? await API.client.messages(requestID: requestID, afterID: lastMessageID), !fresh.isEmpty {
            let known = Set(messages.map(\.id))
            let added = fresh.filter { !known.contains($0.id) }
            if !added.isEmpty {
                withAnimation(.snappy) { messages.append(contentsOf: added) }
                changed = true
            }
        }
        if let fresh = try? await API.client.request(id: requestID), fresh != request {
            let previous = request?.status
            withAnimation(.snappy) { request = fresh }
            if previous == .pending, fresh.status == .accepted, badgeSnapshot == nil {
                badgeSnapshot = try? await API.client.badges()
            }
            // The other phone marked the exchange done: celebrate here too.
            if previous == .accepted, fresh.status == .completed, !completedHere {
                await celebrate()
            }
            changed = true
        }
        return changed
    }

    func send(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let pending = Outgoing(body: String(trimmed.prefix(1000)))
        withAnimation(.snappy) { outgoing.append(pending) }
        Task { await deliver(pending) }
    }

    func retry(_ pending: Outgoing) {
        guard let index = outgoing.firstIndex(of: pending) else { return }
        outgoing[index].failed = false
        Task { await deliver(outgoing[index]) }
    }

    private func deliver(_ pending: Outgoing) async {
        do {
            let message = try await API.client.sendMessage(requestID: requestID, body: pending.body)
            withAnimation(.snappy) {
                outgoing.removeAll { $0.id == pending.id }
                if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
                messages.sort { $0.id < $1.id }
            }
        } catch {
            if let index = outgoing.firstIndex(where: { $0.id == pending.id }) { outgoing[index].failed = true }
        }
    }

    func perform(_ action: RequestAction, toasts: ToastCenter) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if action == .complete {
                completedHere = true
                if badgeSnapshot == nil { badgeSnapshot = try? await API.client.badges() }
            }
            let updated = try await API.client.perform(action, requestID: requestID)
            withAnimation(.snappy) { request = updated }
            if action == .complete { await celebrate() }
            if action == .accept, badgeSnapshot == nil { badgeSnapshot = try? await API.client.badges() }
        } catch {
            if action == .complete { completedHere = false }
            toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
        }
    }

    /// Compare badges with the snapshot from before the exchange, and fetch the item's impact.
    private func celebrate() async {
        guard let request else { return }
        async let listingResult = try? API.client.listing(id: request.listing.id)
        async let badgesResult = try? API.client.badges()
        let (listing, badges) = await (listingResult, badgesResult)
        let earnedBefore = Set((badgeSnapshot ?? []).filter(\.isEarned).map(\.id))
        let newBadges = (badges ?? []).filter { $0.isEarned && !earnedBefore.contains($0.id) }
        celebration = Celebration(impact: listing?.impact ?? .zero, newBadges: badgeSnapshot == nil ? [] : newBadges)
        badgeSnapshot = badges
    }
}
