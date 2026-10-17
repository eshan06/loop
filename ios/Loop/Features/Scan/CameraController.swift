import AVFoundation
import SwiftUI
import UIKit

/// A small AVFoundation wrapper: back camera preview and still capture.
/// In the Simulator there's no camera, so `isAvailable` is false and the flow uses the photo library.
final class CameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    enum Authorization { case unknown, authorized, denied }

    let session = AVCaptureSession()
    @Published private(set) var authorization: Authorization = .unknown
    @Published private(set) var isAvailable = false

    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.stacked.loop.camera")
    private var continuation: CheckedContinuation<UIImage?, Never>?
    private var configured = false

    func prepare() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var granted = status == .authorized
        if status == .notDetermined {
            granted = await AVCaptureDevice.requestAccess(for: .video)
        }
        await MainActor.run { authorization = granted ? .authorized : .denied }
        guard granted else { return }
        let available = await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            queue.async {
                done.resume(returning: self.configure())
            }
        }
        await MainActor.run { isAvailable = available }
        if available { start() }
    }

    private func configure() -> Bool {
        if configured { return true }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return false }
        session.beginConfiguration()
        session.sessionPreset = .photo
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        output.maxPhotoQualityPrioritization = .balanced
        session.commitConfiguration()
        configured = true
        return true
    }

    func start() {
        queue.async { if self.configured, !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture() async -> UIImage? {
        guard isAvailable else { return nil }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .balanced
            queue.async { self.output.capturePhoto(with: settings, delegate: self) }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        continuation?.resume(returning: image)
        continuation = nil
    }
}

/// Live camera preview.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
