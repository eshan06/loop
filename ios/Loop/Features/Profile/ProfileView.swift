import SwiftUI

@MainActor struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(Router.self) private var router
    @Environment(ListingCache.self) private var cache
    @Environment(SavedStore.self) private var saved
    @Environment(NotificationStore.self) private var notifications

    @State private var impact: MyImpact?
    @State private var badges: [Badge] = []
    @State private var status: MyListingsStatus = .active
    @State private var activeIDs: [Int]?
    @State private var completedIDs: [Int]?
    @State private var error: String?
    @State private var showSettings = false
    @State private var selectedBadge: Badge?

    private var ids: [Int]? { status == .active ? activeIDs : completedIDs }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    header
                    impactStrip
                    badgeRow.id("badges")
                    listingsSection
                }
                .padding(Theme.margin)
                .padding(.bottom, 96)
            }
            .onChange(of: router.focusBadges) { _, focus in
                guard focus else { return }
                withAnimation(.snappy) { proxy.scrollTo("badges", anchor: .center) }
                router.focusBadges = false
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: cache.revision) { _, _ in Task { await load() } }
        .onChange(of: notifications.lastBadgeID) { _, _ in Task { await load() } }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            Avatar(url: session.user?.avatarUrl, name: session.user?.name ?? "", size: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(session.user?.name ?? "Loop member").font(.title2.bold())
                Text([session.user?.dorm, session.user?.classYear.map { "Class of \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var impactStrip: some View {
        Button { router.push(.impact) } label: {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text("Your impact").font(.headline)
                    Spacer()
                    Text("Leaderboard").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Theme.textSecondary)
                }
                ImpactStats(impact: impact?.impact ?? .zero)
                    .redacted(reason: impact == nil ? .placeholder : [])
            }
            .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(PressableStyle())
    }

    private var badgeRow: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Badges").font(.headline)
            HStack(spacing: Theme.Space.l) {
                ForEach(badges) { badge in
                    Button { selectedBadge = badge } label: {
                        VStack(spacing: 6) {
                            BadgeIcon(badge: badge)
                            Text(badge.name).font(.caption.weight(.medium)).lineLimit(1)
                            Text(badge.isEarned ? "Earned" : "\(badge.progress) of \(badge.goal)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(badge.isEarned ? Theme.textPrimary : Theme.textSecondary)
                    }
                    .buttonStyle(PressableStyle())
                    .popover(isPresented: Binding(get: { selectedBadge?.id == badge.id },
                                                  set: { if !$0 { selectedBadge = nil } })) {
                        BadgeDetail(badge: badge).presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
    }

    private var listingsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("My listings").font(.headline)
            Picker("Status", selection: $status) {
                Text("Active").tag(MyListingsStatus.active)
                Text("Completed").tag(MyListingsStatus.completed)
            }
            .pickerStyle(.segmented)

            if let ids {
                let listings = cache.resolve(ids)
                if listings.isEmpty {
                    EmptyState(systemImage: status == .active ? "camera" : "checkmark.seal",
                               title: status == .active ? "Nothing listed" : "No exchanges yet",
                               message: status == .active ? "Scan something you don't wear anymore." : "Completed exchanges show up here.",
                               actionTitle: status == .active ? "Scan an item" : nil) { router.isScanPresented = true }
                        .frame(minHeight: 260)
                } else {
                    ListingGrid(listings: listings)
                }
            } else if let error {
                ErrorState(message: error) { Task { await load() } }
            } else {
                ListingGridSkeleton(count: 2)
            }
        }
    }

    // MARK: Data

    private func load() async {
        async let impactResult = try? API.client.myImpact()
        async let badgesResult = try? API.client.badges()
        async let activeResult = API.client.myListings(status: .active)
        async let completedResult = API.client.myListings(status: .completed)
        await session.refresh()
        let (impact, badges) = await (impactResult, badgesResult)
        withAnimation(.smooth) {
            if let impact { self.impact = impact }
            if let badges { self.badges = badges }
        }
        do {
            let (active, completed) = try await (activeResult, completedResult)
            cache.upsert(active.items + completed.items)
            withAnimation(.snappy) {
                activeIDs = active.items.map(\.id)
                completedIDs = completed.items.map(\.id)
            }
            error = nil
        } catch {
            if !error.isCancellation { self.error = error.userMessage }
        }
    }
}

@MainActor private struct BadgeDetail: View {
    let badge: Badge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(badge.name).font(.headline)
            Text(badge.description).font(.subheadline)
            if let earned = badge.earnedAt {
                Text("Earned \(earned.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                ProgressView(value: Double(badge.progress), total: Double(max(badge.goal, 1)))
                Text("\(badge.progress) of \(badge.goal)").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding()
        .frame(width: 240, alignment: .leading)
    }
}

@MainActor struct SettingsSheet: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var showEdit = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("Edit profile") { showEdit = true }
                }
                Section {
                    LabeledContent("Email", value: session.user?.email ?? "")
                    LabeledContent("Campus", value: session.user?.campus.name ?? "")
                    LabeledContent("Data", value: APIConfig.useMocks ? "Mock (offline)" : "Live server")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        dismiss()
                        session.signOut()
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showEdit) { ProfileSetupView(isEditing: true) }
        }
        .presentationDetents([.medium, .large])
    }
}
