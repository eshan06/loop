import SwiftUI

/// The three guided shots for one scan, and the on-device labels computed as each one lands.
@Observable @MainActor
final class ScanSession {
    static let steps: [PhotoKind] = [.front, .back, .label]

    private(set) var shots: [PhotoKind: UIImage] = [:]
    private(set) var skipped: Set<PhotoKind> = []
    var step: PhotoKind = .front
    private var labelTasks: [PhotoKind: Task<[String], Never>] = [:]

    /// The photos to upload, in order front, back, label.
    var orderedShots: [(kind: PhotoKind, image: UIImage)] {
        Self.steps.compactMap { kind in shots[kind].map { (kind, $0) } }
    }

    var isComplete: Bool { shots[.front] != nil && (shots[.label] != nil || skipped.contains(.label)) }

    func add(_ image: UIImage, for kind: PhotoKind) {
        let upright = image.normalizedOrientation()
        shots[kind] = upright
        skipped.remove(kind)
        labelTasks[kind] = Task { await OnDeviceLabeler.labels(for: upright, readText: kind == .label) }
        advance(from: kind)
    }

    func skip(_ kind: PhotoKind) {
        guard kind != .front else { return }
        skipped.insert(kind)
        advance(from: kind)
    }

    func retake(_ kind: PhotoKind) {
        step = kind
    }

    /// Move to the next step that has neither a photo nor a skip.
    private func advance(from kind: PhotoKind) {
        let start = (Self.steps.firstIndex(of: kind) ?? 0) + 1
        if let next = Self.steps[start...].first(where: { shots[$0] == nil && !skipped.contains($0) }) {
            step = next
        } else if let missing = Self.steps.first(where: { shots[$0] == nil && !skipped.contains($0) }) {
            step = missing
        }
    }

    /// Labels from every shot, waiting for any still running.
    func labels() async -> [String] {
        var all: [String] = []
        for kind in Self.steps {
            if let task = labelTasks[kind] { all.append(contentsOf: await task.value) }
        }
        var seen = Set<String>()
        return all.filter { seen.insert($0.lowercased()).inserted }
    }

    func reset() {
        shots = [:]
        skipped = []
        step = .front
        labelTasks = [:]
    }
}

extension PhotoKind {
    var stepTitle: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .label: "Label"
        case .other: "Photo"
        case .avatar: "Avatar"
        }
    }

    var stepHint: String {
        switch self {
        case .front: "Lay it flat or hang it up, whole item in frame"
        case .back: "Flip it over"
        case .label: "Get the tag in frame"
        default: ""
        }
    }
}
