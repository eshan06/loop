import UIKit
import Vision

/// Apple Vision labels for the scan's fallback path (docs/ARCHITECTURE.md, "The scan pipeline").
/// Runs right after each capture; the app always sends the result as `labels` to `POST /scan`,
/// and the server ignores it when the vision model works.
///
/// The labels are insurance, so they must never hold up a scan: Vision runs on its own thread with a
/// deadline, and whatever it has produced by then (classification first, then text) is returned.
enum OnDeviceLabeler {
    /// How long a photo's labels may take before the scan goes ahead without the rest.
    static let deadline: TimeInterval = 8

    /// Top classification labels, plus text read off the label photo.
    static func labels(for image: UIImage, readText: Bool, deadline: TimeInterval = OnDeviceLabeler.deadline) async -> [String] {
        guard let cgImage = image.normalizedOrientation().cgImage else { return [] }
        let collected = Collected()
        return await withCheckedContinuation { continuation in
            let once = Once()
            DispatchQueue.global(qos: .userInitiated).async {
                run(cgImage, readText: readText, into: collected)
                if once.fire() { continuation.resume(returning: collected.labels) }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) {
                if once.fire() { continuation.resume(returning: collected.labels) }
            }
        }
    }

    private static func run(_ cgImage: CGImage, readText: Bool, into collected: Collected) {
        let handler = VNImageRequestHandler(cgImage: cgImage)

        let classify = VNClassifyImageRequest()
        try? handler.perform([classify])
        collected.append((classify.results ?? [])
            .filter { $0.confidence >= 0.3 }
            .sorted { $0.confidence > $1.confidence }
            .prefix(5)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") })

        guard readText else { return }
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        try? handler.perform([text])
        collected.append((text.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .filter { $0.count > 1 }
            .prefix(8)
            .map { $0 })
    }

    /// Labels gathered so far, safe to read from the timeout while Vision is still working.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [String] = []

        func append(_ new: [String]) {
            lock.lock(); defer { lock.unlock() }
            // Commas separate labels in the form field.
            items.append(contentsOf: new.map { $0.replacingOccurrences(of: ",", with: " ") })
        }

        var labels: [String] {
            lock.lock(); defer { lock.unlock() }
            return items
        }
    }

    /// Lets exactly one of two racing callbacks resume the continuation.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        func fire() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }
}
