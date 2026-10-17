import PhotosUI
import SwiftUI

/// Profile setup after the first login, and profile editing from settings.
@MainActor struct ProfileSetupView: View {
    var isEditing = false

    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var classYear: Int?
    @State private var dorm = ""
    @State private var dorms: [String] = []
    @State private var sizes = Sizes()
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarImage: UIImage?
    @State private var avatarPhotoID: Int?
    @State private var isUploadingAvatar = false
    @State private var isSaving = false
    @State private var error: String?
    @State private var loaded = false

    private var years: [Int] {
        let now = Calendar.current.component(.year, from: .now)
        return Array(now...(now + 4))
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isUploadingAvatar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    avatarPicker
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                }

                Section("You") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    Picker("Class year", selection: $classYear) {
                        Text("Not set").tag(Int?.none)
                        ForEach(years, id: \.self) { Text(String($0)).tag(Int?.some($0)) }
                    }
                }

                Section("Where you live") {
                    if dorms.isEmpty {
                        TextField("Dorm", text: $dorm)
                    } else {
                        Picker("Dorm", selection: $dorm) {
                            Text("Choose").tag("")
                            ForEach(dorms, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }

                Section {
                    sizePicker("Tops", options: SizeVocabulary.letter, selection: $sizes.top)
                    sizePicker("Bottoms", options: SizeVocabulary.waist + SizeVocabulary.letter, selection: $sizes.bottom)
                    sizePicker("Shoes", options: SizeVocabulary.shoe, selection: $sizes.shoe)
                } header: {
                    Text("Your sizes")
                } footer: {
                    Text("Optional. Helps you find things that fit.")
                }

                if let error {
                    Section { Text(error).foregroundStyle(Theme.destructive) }
                }
            }
            .scrollContentBackground(.hidden)
            .screenBackground()
            .navigationTitle(isEditing ? "Edit profile" : "Set up your profile")
            .navigationBarTitleDisplayMode(isEditing ? .inline : .large)
            .toolbar {
                if isEditing {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                if isEditing {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Done", action: save).bold().disabled(!canSave)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isEditing {
                    PrimaryButton(title: "Done", isLoading: isSaving, isEnabled: canSave, action: save)
                        .padding(.horizontal, Theme.margin)
                        .padding(.bottom, Theme.Space.xs)
                }
            }
        }
        .task { await load() }
        .onChange(of: avatarItem) { _, item in
            guard let item else { return }
            Task { await uploadAvatar(item) }
        }
    }

    private var avatarPicker: some View {
        PhotosPicker(selection: $avatarItem, matching: .images) {
            VStack(spacing: Theme.Space.xs) {
                ZStack {
                    Circle().fill(Theme.surface)
                    if let avatarImage {
                        Image(uiImage: avatarImage).resizable().scaledToFill()
                    } else if let url = session.user?.avatarUrl {
                        CachedImage(url: url, maxPixel: 300)
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(Color(uiColor: .systemGray3))
                    }
                    if isUploadingAvatar { ProgressView() }
                }
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                Text(avatarImage == nil && session.user?.avatarUrl == nil ? "Add photo" : "Change photo")
                    .font(.subheadline.weight(.medium))
            }
        }
        .buttonStyle(.plain)
    }

    private func sizePicker(_ title: String, options: [String], selection: Binding<String?>) -> some View {
        Picker(title, selection: selection) {
            Text("Not set").tag(String?.none)
            ForEach(options, id: \.self) { Text($0).tag(String?.some($0)) }
        }
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        if let user = session.user {
            name = user.name ?? ""
            classYear = user.classYear
            dorm = user.dorm ?? ""
            sizes = user.sizes
        }
        dorms = (try? await API.client.dorms()) ?? []
        if !dorms.isEmpty, !dorms.contains(dorm) { dorm = "" }
    }

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        avatarImage = image
        isUploadingAvatar = true
        defer { isUploadingAvatar = false }
        do {
            let photo = try await API.client.uploadPhoto(ImageProcessing.jpeg(image), kind: .avatar)
            avatarPhotoID = photo.id
        } catch {
            self.error = error.userMessage
            avatarImage = nil
        }
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        error = nil
        let update = ProfileUpdate(name: name.trimmingCharacters(in: .whitespaces),
                                   dorm: dorm.isEmpty ? nil : dorm,
                                   classYear: classYear,
                                   sizes: sizes,
                                   avatarPhotoId: avatarPhotoID)
        Task {
            defer { isSaving = false }
            do {
                let user = try await API.client.updateMe(update)
                session.update(user)
                if isEditing { dismiss() }
            } catch {
                self.error = error.userMessage
            }
        }
    }
}
