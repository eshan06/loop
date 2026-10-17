import SwiftUI

/// One screen for a request and its chat: header card with actions, the note, then messages.
@MainActor struct ThreadView: View {
    let requestID: Int

    @Environment(SessionStore.self) private var session
    @Environment(ListingCache.self) private var cache
    @Environment(ToastCenter.self) private var toasts
    @Environment(NotificationStore.self) private var notifications
    @Environment(Router.self) private var router

    @State private var model: ThreadModel
    @State private var draft = ""
    @State private var showComplete = false
    @State private var showCancel = false
    @State private var isNearBottom = true
    @FocusState private var composerFocused: Bool

    init(requestID: Int) {
        self.requestID = requestID
        _model = State(initialValue: ThreadModel(requestID: requestID))
    }

    private var myID: Int? { session.userID }

    private var title: String {
        guard let request = model.request else { return "Chat" }
        return request.otherPerson(for: myID).displayName
    }

    private var canCancel: Bool {
        guard let request = model.request else { return false }
        return !request.isOwner(myID) && (request.status == .pending || request.status == .accepted)
    }

    private func retryLoad() {
        model.stop()
        model.start { notifications.refreshCounts() }
    }

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { cancelMenu }
            .onAppear { model.start { notifications.refreshCounts() } }
            .onDisappear { model.stop() }
            .confirmationDialog("Mark this exchange as done?", isPresented: $showComplete, titleVisibility: .visible) {
                Button("Mark as done") { run(.complete) }
            } message: {
                Text("This moves the item to Completed.")
            }
            .confirmationDialog("Cancel this request?", isPresented: $showCancel, titleVisibility: .visible) {
                Button("Cancel request", role: .destructive) { run(.cancel) }
                Button("Keep it", role: .cancel) {}
            }
            .fullScreenCover(item: $model.celebration) { celebration in
                CelebrationView(celebration: celebration)
            }
            .sensoryFeedback(.success, trigger: model.request?.status)
    }

    @ViewBuilder
    private var content: some View {
        if let request = model.request {
            thread(request)
        } else if let error = model.error {
            ErrorState(message: error, retry: retryLoad)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var cancelMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if canCancel {
                Menu {
                    Button("Cancel request", role: .destructive) { showCancel = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func thread(_ request: ExchangeRequest) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 4) {
                    if let note = request.note {
                        NoteBubble(note: note, isMine: request.requester.id == myID, name: request.requester.firstName)
                            .padding(.bottom, Theme.Space.s)
                    }
                    ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? model.messages[index - 1] : nil
                        if previous == nil || message.createdAt.timeIntervalSince(previous!.createdAt) > 600 {
                            Text(message.createdAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.vertical, 8)
                        }
                        MessageBubble(text: message.body, isMine: message.senderId == myID,
                                      groupedWithPrevious: previous?.senderId == message.senderId)
                            .id(message.id)
                    }
                    ForEach(model.outgoing) { pending in
                        MessageBubble(text: pending.body, isMine: true, groupedWithPrevious: true,
                                      isPending: !pending.failed, failed: pending.failed)
                            .onTapGesture { if pending.failed { model.retry(pending) } }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { isNearBottom = true }
                        .onDisappear { isNearBottom = false }
                }
                .padding(.horizontal, Theme.margin)
                .padding(.vertical, Theme.Space.s)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
            .onChange(of: model.messages.count) { _, _ in
                if isNearBottom { withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: model.outgoing.count) { _, _ in
                withAnimation(.snappy) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .safeAreaInset(edge: .top, spacing: 0) { header(request) }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer(request) }
        }
    }

    // MARK: Header

    private func header(_ request: ExchangeRequest) -> some View {
        VStack(spacing: Theme.Space.s) {
            Button {
                router.push(.listing(request.listing.id))
            } label: {
                HStack(spacing: Theme.Space.s) {
                    CachedImage(url: request.listing.photoUrl, maxPixel: 200)
                        .frame(width: 44, height: 55)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.listing.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        HStack(spacing: 6) {
                            StatusPill(status: request.status)
                            ShareTypeCapsule(shareType: request.listing.shareType)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                }
                .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.plain)

            actions(request)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, Theme.Space.s)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .disabled(model.isWorking)
    }

    @ViewBuilder
    private func actions(_ request: ExchangeRequest) -> some View {
        switch request.status {
        case .pending where request.isOwner(myID):
            HStack(spacing: Theme.Space.xs) {
                PrimaryButton(title: "Accept", isLoading: model.isWorking) { run(.accept) }
                SecondaryButton(title: "Decline", role: .destructive) { run(.decline) }
            }
        case .accepted:
            PrimaryButton(title: "Mark exchange done", systemImage: "checkmark.seal", isLoading: model.isWorking) {
                showComplete = true
            }
        default:
            EmptyView()
        }
    }

    // MARK: Composer

    @ViewBuilder
    private func composer(_ request: ExchangeRequest) -> some View {
        Group {
            switch request.status {
            case .accepted:
                HStack(alignment: .bottom, spacing: Theme.Space.xs) {
                    TextField("Message", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .accessibilityIdentifier("composer")
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    Button {
                        model.send(draft)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color(uiColor: .systemGray3) : Theme.accent, in: Circle())
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Send message")
                }
            case .pending:
                statusNote("Chat opens once the request is accepted.", systemImage: "lock")
            case .completed:
                statusNote("Exchange complete. Thanks for keeping clothes in the loop.", systemImage: "checkmark.seal")
            case .declined:
                statusNote("This request was declined.", systemImage: "xmark.circle")
            case .cancelled:
                statusNote("This request was cancelled.", systemImage: "xmark.circle")
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, Theme.Space.xs)
        .background(.bar)
    }

    private func statusNote(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 40)
    }

    private func run(_ action: RequestAction) {
        Task {
            await model.perform(action, toasts: toasts)
            cache.invalidate()
            notifications.refreshCounts()
        }
    }
}

// MARK: - Bubbles

@MainActor struct MessageBubble: View {
    let text: String
    let isMine: Bool
    var groupedWithPrevious = false
    var isPending = false
    var failed = false

    var body: some View {
        HStack {
            if isMine { Spacer(minLength: 60) }
            VStack(alignment: .trailing, spacing: 2) {
                Text(text)
                    .font(.body)
                    .foregroundStyle(isMine ? Color.white : Theme.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(failed ? Theme.destructive : (isMine ? Theme.accent : Theme.surface),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .opacity(isPending ? 0.55 : 1)
                if failed {
                    Label("Tap to retry", systemImage: "exclamationmark.circle")
                        .font(.caption2)
                        .foregroundStyle(Theme.destructive)
                }
            }
            if !isMine { Spacer(minLength: 60) }
        }
        .padding(.top, groupedWithPrevious ? 0 : 6)
    }
}

@MainActor private struct NoteBubble: View {
    let note: String
    let isMine: Bool
    let name: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(isMine ? "Your request note" : "Request note from \(name)", systemImage: "hand.raised")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Text(note).font(.callout)
        }
        .padding(Theme.Space.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
    }
}
