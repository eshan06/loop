import SwiftUI

/// Category grid and a size picker that adapts to the category.
@MainActor struct FilterSheet: View {
    @Binding var category: ItemCategory?
    @Binding var size: String?
    @Environment(\.dismiss) private var dismiss

    @State private var draftCategory: ItemCategory?
    @State private var draftSize: String?

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: Theme.Space.xs)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Category").font(.headline)
                        LazyVGrid(columns: columns, spacing: Theme.Space.xs) {
                            ForEach(ItemCategory.allCases) { item in
                                Button {
                                    draftCategory = draftCategory == item ? nil : item
                                    if let current = draftSize, SizeVocabulary.match(current, in: draftCategory) == nil {
                                        draftSize = nil
                                    }
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: item.symbol).font(.system(size: 20))
                                        Text(item.label).font(.footnote.weight(.medium))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 68)
                                    .foregroundStyle(draftCategory == item ? Color.white : Theme.textPrimary)
                                    .background(draftCategory == item ? Theme.accent : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                                }
                                .buttonStyle(PressableStyle())
                                .sensoryFeedback(.selection, trigger: draftCategory)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.s) {
                        Text("Size").font(.headline)
                        FlowChips(options: SizeVocabulary.options(for: draftCategory), selection: $draftSize)
                    }
                }
                .padding(Theme.margin)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") {
                        draftCategory = nil
                        draftSize = nil
                    }
                    .disabled(draftCategory == nil && draftSize == nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Show results") {
                    category = draftCategory
                    size = draftSize
                    dismiss()
                }
                .padding(.horizontal, Theme.margin)
                .padding(.bottom, Theme.Space.xs)
                .background(.bar)
            }
        }
        .onAppear {
            draftCategory = category
            draftSize = size
        }
    }
}

/// Wrapping single-select chips.
@MainActor struct FlowChips: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        FlowLayout(spacing: Theme.Space.xs) {
            ForEach(options, id: \.self) { option in
                Chip(title: option, isSelected: selection == option) {
                    selection = selection == option ? nil : option
                }
            }
        }
    }
}

/// Lays out children left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
