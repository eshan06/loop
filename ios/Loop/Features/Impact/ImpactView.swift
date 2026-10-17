import SwiftUI

/// Personal totals, campus totals for the week, and the dorm leaderboard.
/// Opened from the Profile impact strip and from the feed's campus banner.
@MainActor struct ImpactView: View {
    @Environment(SessionStore.self) private var session

    @State private var mine: MyImpact?
    @State private var campus: CampusImpact?
    @State private var leaderboard: [LeaderboardEntry]?
    @State private var failed: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xxl) {
                section("You") {
                    if let mine {
                        ImpactStats(impact: mine.impact, large: true)
                        Text("Items shared \(mine.itemsShared) · received \(mine.itemsReceived)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        ImpactStats(impact: .zero, large: true).redacted(reason: .placeholder).shimmer()
                    }
                }

                section("\(session.user?.campus.name ?? "Your campus") this week") {
                    if let campus {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(campus.itemsRehomed)")
                                .font(.roundedNumber(40))
                                .contentTransition(.numericText(value: Double(campus.itemsRehomed)))
                            Text("items rehomed").font(.headline).foregroundStyle(Theme.textSecondary)
                        }
                        ImpactStats(impact: Impact(textileKg: campus.textileKg, waterL: campus.waterL, co2Kg: campus.co2Kg))
                    } else {
                        SkeletonBlock(width: 160, height: 40).shimmer()
                    }
                }

                section("Dorm leaderboard") {
                    if let leaderboard {
                        if leaderboard.isEmpty {
                            Text("No exchanges this week yet. Yours could put your dorm on the board.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            LeaderboardList(entries: leaderboard, myDorm: session.user?.dorm)
                        }
                    } else {
                        VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in SkeletonBlock(height: 44) } }.shimmer()
                    }
                }

                if let failed {
                    Text(failed).font(.footnote).foregroundStyle(Theme.destructive)
                }
            }
            .padding(Theme.margin)
            .padding(.bottom, Theme.Space.xxl)
        }
        .navigationTitle("Impact")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await load() }
        .task { await load() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text(title).font(.title3.bold())
            content()
        }
    }

    private func load() async {
        async let mineResult = API.client.myImpact()
        async let campusResult = API.client.campusImpact()
        async let boardResult = API.client.leaderboard()
        do {
            let (mine, campus, board) = try await (mineResult, campusResult, boardResult)
            withAnimation(.smooth) {
                self.mine = mine
                self.campus = campus
                self.leaderboard = board
            }
            failed = nil
        } catch {
            if !error.isCancellation { failed = error.userMessage }
        }
    }
}

/// Textile, water, CO₂ with a relatable comparison under each.
@MainActor struct ImpactStats: View {
    let impact: Impact
    var large = false

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            stat(value: impact.textileKg, unit: "kg", label: "textile", comparison: ImpactComparison.tshirts(impact.textileKg))
            stat(value: impact.waterL, unit: "L", label: "water", comparison: ImpactComparison.showers(impact.waterL))
            stat(value: impact.co2Kg, unit: "kg", label: "CO₂", comparison: ImpactComparison.miles(impact.co2Kg))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stat(value: Double, unit: String, label: String, comparison: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(ImpactFormat.number(value))
                    .font(.roundedNumber(large ? 28 : 20))
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            }
            Text(label).font(.subheadline.weight(.medium))
            if large, let comparison {
                Text(comparison).font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Theme.Space.s)
        .cardBackground()
    }
}

@MainActor struct LeaderboardList: View {
    let entries: [LeaderboardEntry]
    let myDorm: String?

    private var top: Int { entries.map(\.itemsShared).max() ?? 1 }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(entries, id: \.dorm) { entry in
                let isMine = entry.dorm == myDorm
                HStack(spacing: Theme.Space.s) {
                    Text("\(entry.rank)")
                        .font(.roundedNumber(17))
                        .frame(width: 26, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(entry.dorm).font(isMine ? .subheadline.bold() : .subheadline)
                            if isMine { TagCapsule(text: "You", filled: true) }
                            Spacer()
                            Text("\(entry.itemsShared)").font(.roundedNumber(15))
                        }
                        GeometryReader { proxy in
                            Capsule()
                                .fill(Theme.accent.opacity(isMine ? 1 : 0.8))
                                .frame(width: max(4, proxy.size.width * CGFloat(entry.itemsShared) / CGFloat(max(top, 1))))
                        }
                        .frame(height: 3)
                    }
                }
                .padding(.horizontal, Theme.Space.s)
                .padding(.vertical, 10)
                .background(isMine ? Theme.surface : Color.clear,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            }
        }
    }
}
