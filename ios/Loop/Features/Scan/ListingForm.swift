import SwiftUI

/// The editable fields of a listing, shared by Review (after a scan) and Edit listing.
struct ListingFormState: Equatable {
    var title = ""
    var category: ItemCategory?
    var size: String?
    var color = ""
    var brand = ""
    var condition: Condition?
    var description = ""
    var tags: [String] = []
    var shareType: ShareType?
    var meetupSpotID: Int?

    /// Fill the AI fields from a scan. With `onlyBlank`, fields the user already filled in are kept.
    mutating func apply(_ draft: ScanDraft, onlyBlank: Bool = false) {
        func pick(_ current: String, _ new: String?) -> String {
            onlyBlank && !current.trimmingCharacters(in: .whitespaces).isEmpty ? current : (new ?? current)
        }
        title = pick(title, draft.title)
        color = pick(color, draft.color)
        brand = pick(brand, draft.brand)
        description = pick(description, draft.description)
        if !onlyBlank || category == nil { category = draft.category ?? category }
        if !onlyBlank || size == nil { size = draft.size ?? size }
        if !onlyBlank || condition == nil { condition = draft.condition ?? condition }
        if !onlyBlank || tags.isEmpty { tags = Array(draft.tags.prefix(10)) }
    }

    init() {}

    init(_ listing: Listing) {
        title = listing.title
        category = listing.category
        size = listing.size
        color = listing.color ?? ""
        brand = listing.brand ?? ""
        condition = listing.condition
        description = listing.description ?? ""
        tags = listing.tags
        shareType = listing.shareType
        meetupSpotID = listing.meetupSpot?.id
    }

    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && category != nil && condition != nil
            && shareType != nil && meetupSpotID != nil
    }

    func input(photoIDs: [Int]) -> ListingInput? {
        guard let category, let condition, let shareType, let meetupSpotID else { return nil }
        func clean(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return ListingInput(title: String(title.trimmingCharacters(in: .whitespaces).prefix(120)), category: category,
                            size: size.flatMap(clean), color: clean(color), brand: clean(brand),
                            condition: condition, description: clean(description), tags: tags,
                            shareType: shareType, meetupSpotId: meetupSpotID, photoIds: photoIDs)
    }
}

/// Form sections for the AI fields. `locked` shows skeletons while the scan is running.
@MainActor struct ListingDetailsFields: View {
    @Binding var form: ListingFormState
    var locked = false

    @State private var newTag = ""
    @State private var showOtherSize = false
    @State private var otherSize = ""

    var body: some View {
        Group {
            Section("Item") {
                field { TextField("Title", text: $form.title).dismissKeyboardOnDone() }
                field {
                    Picker("Category", selection: $form.category) {
                        Text("Choose").tag(ItemCategory?.none)
                        ForEach(ItemCategory.allCases) { Text($0.label).tag(ItemCategory?.some($0)) }
                    }
                    .accessibilityIdentifier("categoryPicker")
                }
                field { sizePicker }
                field {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Condition")
                        Picker("Condition", selection: $form.condition) {
                            ForEach(Condition.allCases) { Text($0.label).tag(Condition?.some($0)) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Details") {
                field { TextField("Brand", text: $form.brand).dismissKeyboardOnDone() }
                field { TextField("Color", text: $form.color).dismissKeyboardOnDone() }
                field {
                    TextField("Description", text: $form.description, axis: .vertical)
                        .lineLimit(3...8)
                }
            }

            Section("Tags") {
                field { tagEditor }
            }
        }
        .disabled(locked)
        .onChange(of: form.category) { old, new in
            // Reset the size only when it was a standard option that isn't valid for the new category.
            // Custom "Other" sizes stay.
            if let size = form.size, SizeVocabulary.match(size, in: old) != nil, SizeVocabulary.match(size, in: new) == nil {
                form.size = nil
            }
        }
        .alert("Other size", isPresented: $showOtherSize) {
            TextField("Size", text: $otherSize)
            Button("Use size") {
                let trimmed = otherSize.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { form.size = String(trimmed.prefix(20)) }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func field<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if locked {
            SkeletonBlock(height: 18).frame(maxWidth: .infinity).padding(.vertical, 4).shimmer()
        } else {
            content().transition(.opacity)
        }
    }

    private static let otherTag = "__other__"

    private var sizeSelection: Binding<String?> {
        Binding(get: {
            guard let size = form.size else { return nil }
            return SizeVocabulary.match(size, in: form.category) ?? size
        }, set: { value in
            if value == Self.otherTag {
                otherSize = ""
                showOtherSize = true
            } else {
                form.size = value
            }
        })
    }

    private var sizePicker: some View {
        let options = SizeVocabulary.options(for: form.category)
        let custom = form.size.flatMap { SizeVocabulary.match($0, in: form.category) == nil ? $0 : nil }
        return Picker("Size", selection: sizeSelection) {
            Text("Not set").tag(String?.none)
            ForEach(options, id: \.self) { Text($0).tag(String?.some($0)) }
            if let custom { Text("Other: \(custom)").tag(String?.some(custom)) }
            Text("Other…").tag(String?.some(Self.otherTag))
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !form.tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(form.tags, id: \.self) { tag in
                        Button {
                            withAnimation(.snappy) { form.tags.removeAll { $0 == tag } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag)
                                Image(systemName: "xmark").font(.caption2.weight(.bold))
                            }
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Theme.surface, in: Capsule())
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            if form.tags.count < 10 {
                TextField("Add a tag", text: $newTag)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    .onSubmit(addTag)
            }
        }
        .padding(.vertical, 4)
    }

    private func addTag() {
        let tag = String(newTag.trimmingCharacters(in: .whitespaces).lowercased().prefix(30))
        guard !tag.isEmpty, !form.tags.contains(tag), form.tags.count < 10 else { newTag = ""; return }
        withAnimation(.snappy) { form.tags.append(tag) }
        newTag = ""
    }
}

/// Share type and meetup spot: the fields the user fills in, editable while the scan runs.
@MainActor struct ShareFields: View {
    @Binding var form: ListingFormState
    let spots: [MeetupSpot]?

    var body: some View {
        Section {
            Picker("Share type", selection: $form.shareType) {
                ForEach(ShareType.allCases) { Text($0.label).tag(ShareType?.some($0)) }
            }
            .pickerStyle(.segmented)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

            if let spots {
                Picker("Meetup spot", selection: $form.meetupSpotID) {
                    Text("Choose").tag(Int?.none)
                    ForEach(spots) { Text($0.name).tag(Int?.some($0.id)) }
                }
                .accessibilityIdentifier("meetupPicker")
            } else {
                HStack { Text("Meetup spot"); Spacer(); ProgressView() }
            }
        } header: {
            Text("How you're sharing it")
        } footer: {
            Text(shareFooter)
        }
    }

    private var shareFooter: String {
        switch form.shareType {
        case .swap: "Swap: trade it for something of theirs."
        case .free: "Free: give it to another student."
        case .donate: "Donate: it goes to a campus donation drive."
        case nil: "Choose how you want to share it."
        }
    }
}

extension View {
    /// Return key says "Done" and puts the keyboard away. Single-line fields keep focus otherwise,
    /// and the keyboard then covers the rows below.
    func dismissKeyboardOnDone() -> some View {
        submitLabel(.done).onSubmit {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}
