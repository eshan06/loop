import UIKit
import Vision

/// Apple Vision labels for the scan's fallback path (docs/ARCHITECTURE.md, "The scan pipeline").
/// Runs right after each capture; the app always sends the result as `labels` to `POST /scan`,
/// and the server ignores it when the vision model works.
enum OnDeviceLabeler {
    /// Top classification labels, plus text read off the label photo.
    static func labels(for image: UIImage, readText: Bool) async -> [String] {
        guard let cgImage = image.normalizedOrientation().cgImage else { return [] }
        return await Task.detached(priority: .utility) {
            let handler = VNImageRequestHandler(cgImage: cgImage)
            let classify = VNClassifyImageRequest()
            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            let requests: [VNRequest] = readText ? [classify, text] : [classify]
            try? handler.perform(requests)

            var labels = (classify.results ?? [])
                .filter { $0.confidence >= 0.3 }
                .prefix(5)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
            if readText {
                let words = (text.results ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .filter { $0.count > 1 }
                    .prefix(8)
                labels.append(contentsOf: words)
            }
            // Commas separate labels in the form field.
            return labels.map { $0.replacingOccurrences(of: ",", with: " ") }
        }.value
    }
}
