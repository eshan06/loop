import SwiftUI

/// Two or three outfit ideas from the text model. On `ai_unavailable` the sheet closes with a toast.
struct StyleItSheet: View {
    let listing: Listing

    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var ideas: [StyleIdea]?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.s) {
                    Text("Outfit ideas built around your \(listing.title.lowercased()).")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.bottom, Theme.Space.xxs)
                    if let ideas {
                        ForEach(Array(ideas.enumerated()), id: \.offset) { index, idea in
                            IdeaCard(number: index + 1, idea: idea)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    } else {
                        ForEach(0..<3, id: \.self) { _ in skeletonCard }
                    }
                }
                .padding(Theme.margin)
                .animation(.smooth, value: ideas)
            }
            .navigationTitle("Style it")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationCornerRadius(Theme.Radius.sheet)
        .task { await load() }
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(width: 140, height: 16)
            SkeletonBlock(height: 12)
            SkeletonBlock(width: 220, height: 12)
        }
        .padding(Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .shimmer()
    }

    private func load() async {
        do {
            ideas = try await API.client.styleIdeas(listingID: listing.id)
        } catch {
            guard !error.isCancellation else { return }
            dismiss()
            toasts.show("Style ideas aren't available right now.", systemImage: "sparkles")
        }
    }
}

private struct IdeaCard: View {
    let number: Int
    let idea: StyleIdea

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.s) {
            Text("\(number)")
                .font(.roundedNumber(15))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.accent, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(idea.title).font(.headline)
                Text(idea.description).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Space.m)
        .cardBackground()
    }
}
