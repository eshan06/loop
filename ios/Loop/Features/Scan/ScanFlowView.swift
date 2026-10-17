import PhotosUI
import SwiftUI

/// Camera → Review, presented full screen from the raised Scan button.
@MainActor struct ScanFlowView: View {
    @State private var scan = ScanSession()
    @State private var path: [ScanStep] = []

    enum ScanStep: Hashable { case review }

    var body: some View {
        NavigationStack(path: $path) {
            CameraView(scan: scan) { path = [.review] }
                .navigationDestination(for: ScanStep.self) { _ in
                    ReviewView(shots: scan.orderedShots, labels: { await scan.labels() })
                }
        }
        .tint(Theme.accent)
    }
}

/// Full-screen preview with one continuous flow: Front, then Back, then Label.
@MainActor struct CameraView: View {
    @Bindable var scan: ScanSession
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = CameraController()
    @State private var libraryItem: PhotosPickerItem?
    @State private var showSkipLabel = false
    @State private var flash = false
    @State private var captureCount = 0
    @State private var isCapturing = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if camera.isAvailable {
                CameraPreview(session: camera.session).ignoresSafeArea()
            } else {
                unavailable
            }
            if camera.isAvailable { guide }
            Color.white.opacity(flash ? 0.7 : 0).ignoresSafeArea().allowsHitTesting(false)
            VStack {
                topBar
                Spacer()
                bottomBar
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden()
        .task { await camera.prepare() }
        .onDisappear { camera.stop() }
        .onAppear { camera.start() }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                // Decode straight to at most 2400 px with ImageIO, so a huge HEIC from the library never
                // becomes a full-size bitmap. It also applies the photo's orientation.
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = await Task.detached(priority: .userInitiated, operation: {
                       ImageLoader.downsample(data, maxPixel: 2400)
                   }).value {
                    accept(image)
                }
                libraryItem = nil
            }
        }
        .confirmationDialog("The label helps us read the brand and size. Skip anyway?",
                            isPresented: $showSkipLabel, titleVisibility: .visible) {
            Button("Take label photo") {}
            Button("Skip") {
                scan.skip(.label)
                finishIfDone()
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: captureCount)
    }

    // MARK: Pieces

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial.opacity(0.8), in: Circle())
            }
            .environment(\.colorScheme, .dark)
            Spacer()
            VStack(spacing: 2) {
                Text(scan.step.stepTitle).font(.headline)
                Text("Step \((ScanSession.steps.firstIndex(of: scan.step) ?? 0) + 1) of 3").font(.caption)
            }
            .foregroundStyle(.white)
            .contentTransition(.opacity)
            .animation(.snappy, value: scan.step)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, Theme.Space.xs)
    }

    private var guide: some View {
        GeometryReader { proxy in
            let isLabel = scan.step == .label
            let width = proxy.size.width * (isLabel ? 0.5 : 0.78)
            let height = isLabel ? width * 0.7 : width * 1.25
            VStack(spacing: Theme.Space.s) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(.white.opacity(0.85), style: StrokeStyle(lineWidth: 2, dash: [10, 8]))
                    .frame(width: width, height: height)
                Text(scan.step.stepHint)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.35), in: Capsule())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -30)
            .animation(.snappy, value: scan.step)
        }
        .allowsHitTesting(false)
    }

    private var bottomBar: some View {
        VStack(spacing: Theme.Space.l) {
            if scan.step != .front {
                Button("Skip") {
                    if scan.step == .label { showSkipLabel = true } else { scan.skip(scan.step); finishIfDone() }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.black.opacity(0.35), in: Capsule())
            }

            HStack {
                PhotosPicker(selection: $libraryItem, matching: .images) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(.white.opacity(0.18), in: Circle())
                }
                .accessibilityLabel("Choose from library")

                Spacer()
                Button(action: capture) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                        Circle().fill(.white).frame(width: 64, height: 64)
                            .scaleEffect(isCapturing ? 0.86 : 1)
                    }
                }
                .disabled(!camera.isAvailable || isCapturing)
                .opacity(camera.isAvailable ? 1 : 0.35)
                .accessibilityLabel("Take photo")
                Spacer()

                thumbnails
            }
            .padding(.horizontal, Theme.xlMargin)
        }
        .padding(.bottom, Theme.Space.l)
    }

    private var thumbnails: some View {
        HStack(spacing: 4) {
            ForEach(ScanSession.steps, id: \.self) { kind in
                Button { scan.retake(kind) } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(scan.step == kind ? Color.white : .white.opacity(0.4), lineWidth: scan.step == kind ? 2 : 1)
                        if let image = scan.shots[kind] {
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 26, height: 34)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        } else if scan.skipped.contains(kind) {
                            Image(systemName: "minus").font(.caption2).foregroundStyle(.white.opacity(0.6))
                        }
                    }
                    .frame(width: 28, height: 36)
                }
                .disabled(scan.shots[kind] == nil && !scan.skipped.contains(kind))
                .transition(.scale)
            }
        }
        .frame(width: 92)
        .animation(.snappy, value: scan.shots.count)
    }

    private var unavailable: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: camera.authorization == .denied ? "camera.badge.ellipsis" : "camera")
                .font(.system(size: 44))
            Text(camera.authorization == .denied ? "Camera access is off" : "Camera isn't available here")
                .font(.headline)
            Text("Choose photos from your library instead.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))
            #if DEBUG
            Button("Use sample photos") {
                for (index, kind) in ScanSession.steps.enumerated() {
                    let url = URL(string: "mock://media/outerwear-sample-\(index).jpg")!
                    scan.add(PlaceholderArt.image(for: url), for: kind)
                }
                onFinish()
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .accessibilityIdentifier("sampleBtn")
            #endif
            if camera.authorization == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        .foregroundStyle(.white)
        .padding(.bottom, 120)
    }

    // MARK: Actions

    private func capture() {
        isCapturing = true
        withAnimation(.easeOut(duration: 0.08)) { flash = true }
        Task {
            let image = await camera.capture()
            withAnimation(.easeIn(duration: 0.25)) { flash = false }
            isCapturing = false
            if let image { accept(image) }
        }
    }

    private func accept(_ image: UIImage) {
        captureCount += 1
        withAnimation(.snappy) { scan.add(image, for: scan.step) }
        finishIfDone()
    }

    private func finishIfDone() {
        if scan.isComplete { onFinish() }
    }
}

private extension Theme {
    static let xlMargin: CGFloat = 28
}
