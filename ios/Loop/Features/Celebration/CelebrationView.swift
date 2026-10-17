import SwiftUI

/// Full-screen moment after an exchange completes: the item's impact counts up from zero,
/// and any badge just earned flips in. Both phones show it.
struct CelebrationView: View {
    let celebration: ThreadModel.Celebration

    @Environment(\.dismiss) private var dismiss
    @State private var shown: Impact = .zero
    @State private var showBadges = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: Theme.Space.xl) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .symbolEffect(.bounce, value: appeared)
            VStack(spacing: Theme.Space.xs) {
                Text("Exchange complete").font(.largeTitle.bold())
                Text("This item stays in the loop.").font(.title3).foregroundStyle(Theme.textSecondary)
            }

            VStack(spacing: Theme.Space.s) {
                row(value: shown.textileKg, unit: "kg", label: "textile kept out of landfill",
                    comparison: ImpactComparison.tshirts(celebration.impact.textileKg))
                row(value: shown.waterL, unit: "L", label: "water saved",
                    comparison: ImpactComparison.showers(celebration.impact.waterL))
                row(value: shown.co2Kg, unit: "kg", label: "CO₂ avoided",
                    comparison: ImpactComparison.miles(celebration.impact.co2Kg))
            }
            .padding(.horizontal, Theme.margin)

            if showBadges {
                ForEach(celebration.newBadges) { badge in
                    HStack(spacing: Theme.Space.s) {
                        BadgeIcon(badge: badge, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Badge unlocked").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            Text(badge.name).font(.headline)
                        }
                        Spacer()
                    }
                    .padding(Theme.Space.m)
                    .cardBackground()
                    .padding(.horizontal, Theme.margin)
                    .transition(.asymmetric(insertion: .scale(scale: 0.6).combined(with: .opacity), removal: .opacity))
                    .rotation3DEffect(.degrees(showBadges ? 0 : 90), axis: (x: 0, y: 1, z: 0))
                }
            }

            Spacer()
            PrimaryButton(title: "Done") { dismiss() }
                .padding(.horizontal, Theme.margin)
        }
        .padding(.bottom, Theme.Space.l)
        .background(Theme.background)
        .sensoryFeedback(.success, trigger: appeared)
        .task {
            appeared = true
            try? await Task.sleep(for: .milliseconds(250))
            // Text doesn't interpolate numbers, so step the count-up with an ease-out curve.
            let target = celebration.impact
            let steps = 28
            for step in 1...steps {
                let progress = 1 - pow(1 - Double(step) / Double(steps), 3)
                withAnimation(.snappy(duration: 0.1)) {
                    shown = Impact(textileKg: target.textileKg * progress, waterL: target.waterL * progress,
                                   co2Kg: target.co2Kg * progress)
                }
                try? await Task.sleep(for: .milliseconds(45))
            }
            try? await Task.sleep(for: .milliseconds(200))
            if !celebration.newBadges.isEmpty {
                withAnimation(.spring(duration: 0.6, bounce: 0.35)) { showBadges = true }
            }
        }
    }

    private func row(value: Double, unit: String, label: String, comparison: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(ImpactFormat.number(value))
                    .font(.roundedNumber(34))
                    .contentTransition(.numericText(value: value))
                Text(unit).font(.headline).foregroundStyle(Theme.textSecondary)
            }
            .frame(minWidth: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                if let comparison { Text(comparison).font(.caption).foregroundStyle(Theme.textSecondary) }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Earned: black-filled circle with a white glyph. Not earned: gray outline.
struct BadgeIcon: View {
    let badge: Badge
    var size: CGFloat = 56

    var body: some View {
        ZStack {
            if badge.isEarned {
                Circle().fill(Theme.accent)
            } else {
                Circle().strokeBorder(Color(uiColor: .systemGray3), lineWidth: 1.5)
            }
            Image(systemName: badge.symbol)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(badge.isEarned ? Color.white : Color(uiColor: .systemGray3))
        }
        .frame(width: size, height: size)
    }
}
