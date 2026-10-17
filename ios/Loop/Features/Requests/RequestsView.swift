import SwiftUI

@Observable @MainActor
final class RequestsModel {
    var role: RequestRole = .incoming
    private(set) var incoming: [ExchangeRequest]?
    private(set) var outgoing: [ExchangeRequest]?
    private(set) var error: String?
    private(set) var workingIDs: Set<Int> = []

    var current: [ExchangeRequest]? { role == .incoming ? incoming : outgoing }

    func load() async {
        async let incomingResult = API.client.myRequests(role: .incoming)
        async let outgoingResult = API.client.myRequests(role: .outgoing)
        do {
            let (incoming, outgoing) = try await (incomingResult, outgoingResult)
            withAnimation(.snappy) {
                self.incoming = incoming.items
                self.outgoing = outgoing.items
            }
            error = nil
        } catch {
            if !error.isCancellation, current == nil { self.error = error.userMessage }
        }
    }

    func perform(_ action: RequestAction, on request: ExchangeRequest, cache: ListingCache, toasts: ToastCenter) async -> Bool {
        workingIDs.insert(request.id)
        defer { workingIDs.remove(request.id) }
        do {
            let updated = try await API.client.perform(action, requestID: request.id)
            replace(updated)
            cache.invalidate()
            await load()
            return true
        } catch {
            toasts.show(error.userMessage, systemImage: "exclamationmark.triangle.fill")
            return false
        }
    }

    private func replace(_ request: ExchangeRequest) {
        incoming = incoming?.map { $0.id == request.id ? request : $0 }
        outgoing = outgoing?.map { $0.id == request.id ? request : $0 }
    }
}

/// Requests tab: Incoming | Outgoing, sectioned by status.
@MainActor struct RequestsView: View {
    @Environment(NotificationStore.self) private var notifications
    @State private var model = RequestsModel()

    var body: some View {
        RequestList(model: model, listingID: nil)
            .navigationTitle("Requests")
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Role", selection: $model.role) {
                    Text("Incoming").tag(RequestRole.incoming)
                    Text("Outgoing").tag(RequestRole.outgoing)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.Space.xs)
                .background(Theme.background)
            }
            .task { await model.load() }
            .onChange(of: notifications.requestsRevision) { _, _ in Task { await model.load() } }
            .onAppear { Task { await model.load() } }
    }
}

/// Incoming requests for one of my listings ("N requests" on item detail).
@MainActor struct ListingRequestsView: View {
    let listingID: Int
    let title: String
    @State private var model = RequestsModel()

    var body: some View {
        RequestList(model: model, listingID: listingID)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .task { await model.load() }
    }
}

@MainActor struct RequestList: View {
    @Bindable var model: RequestsModel
    /// Only show incoming requests for this listing.
    let listingID: Int?

    @Environment(SessionStore.self) private var session
    @Environment(ListingCache.self) private var cache
    @Environment(ToastCenter.self) private var toasts
    @Environment(NotificationStore.self) private var notifications
    @State private var accepted = 0

    private var requests: [ExchangeRequest]? {
        guard let listingID else { return model.current }
        return model.incoming?.filter { $0.listing.id == listingID }
    }

    private var role: RequestRole { listingID == nil ? model.role : .incoming }

    private struct RequestSection: Identifiable {
        let title: String
        let items: [ExchangeRequest]
        var id: String { title }
    }

    private var sections: [RequestSection] {
        let items = requests ?? []
        let groups: [(String, [RequestStatus])] = role == .incoming
            ? [("Needs response", [.pending]), ("Active", [.accepted]), ("Past", [.declined, .completed, .cancelled])]
            : [("Waiting", [.pending]), ("Active", [.accepted]), ("Past", [.declined, .completed, .cancelled])]
        return groups.compactMap { title, statuses in
            let matching = items.filter { statuses.contains($0.status) }
            return matching.isEmpty ? nil : RequestSection(title: title, items: matching)
        }
    }

    var body: some View {
        Group {
            if let requests {
                if requests.isEmpty {
                    ScrollView {
                        emptyState.padding(.top, 80)
                    }
                } else {
                    List {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.items) { request in
                                    NavigationLink(value: Route.thread(request.id)) {
                                        RequestRow(request: request, myID: session.userID,
                                                   isWorking: model.workingIDs.contains(request.id),
                                                   onAccept: { act(.accept, request) },
                                                   onDecline: { act(.decline, request) })
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            } else if let error = model.error {
                ErrorState(message: error) { Task { await model.load() } }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .refreshable { await model.load() }
        .screenBackground()
        .sensoryFeedback(.success, trigger: accepted)
    }

    @ViewBuilder
    private var emptyState: some View {
        if role == .incoming {
            EmptyState(systemImage: "tray", title: "No requests yet",
                       message: "Listings with good photos get noticed faster.")
        } else {
            EmptyState(systemImage: "paperplane", title: "Nothing requested",
                       message: "When you request something, it shows up here.")
        }
    }

    private func act(_ action: RequestAction, _ request: ExchangeRequest) {
        Task {
            if await model.perform(action, on: request, cache: cache, toasts: toasts) {
                if action == .accept {
                    accepted += 1
                    toasts.show("Accepted. Chat is open.")
                }
                notifications.refreshCounts()
            }
        }
    }
}

@MainActor struct RequestRow: View {
    let request: ExchangeRequest
    let myID: Int?
    var isWorking = false
    var onAccept: () -> Void = {}
    var onDecline: () -> Void = {}

    private var other: Owner { request.otherPerson(for: myID) }
    private var isIncomingPending: Bool { request.isOwner(myID) && request.status == .pending }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.s) {
                CachedImage(url: request.listing.photoUrl, maxPixel: 200)
                    .frame(width: 48, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay { PhotoHairline(radius: 8) }
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.listing.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text([other.displayName, other.dorm].compactMap { $0 }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        StatusPill(status: request.status)
                        Text(request.updatedAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if request.unreadMessages > 0 {
                    Circle().fill(Theme.accent).frame(width: 9, height: 9)
                        .accessibilityLabel("\(request.unreadMessages) unread")
                }
            }

            if isIncomingPending {
                if let note = request.note {
                    Text("“\(note)”").font(.footnote).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
                HStack(spacing: Theme.Space.xs) {
                    Button(action: onAccept) {
                        Text("Accept")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Theme.accent, in: Capsule())
                    }
                    Button(action: onDecline) {
                        Text("Decline")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(Theme.surface, in: Capsule())
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isWorking)
                .opacity(isWorking ? 0.5 : 1)
            }
        }
        .padding(.vertical, 4)
    }
}
