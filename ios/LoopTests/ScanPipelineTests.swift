import UIKit
import XCTest
@testable import Loop

/// The scan path end to end, minus the camera: session flow, image prep, on-device Vision, request format.
final class ScanPipelineTests: XCTestCase {

    // MARK: Helpers

    private func image(width: CGFloat, height: CGFloat, color: UIColor = .systemTeal, scale: CGFloat = 1) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(of data: Data) -> CGSize? {
        UIImage(data: data).map { CGSize(width: $0.size.width * $0.scale, height: $0.size.height * $0.scale) }
    }

    // MARK: Guided front / back / label flow

    @MainActor
    func testGuidedFlowAdvancesFrontBackLabelAndOrdersShots() {
        let scan = ScanSession()
        XCTAssertEqual(scan.step, .front)
        XCTAssertFalse(scan.isComplete)
        scan.add(image(width: 10, height: 10), for: scan.step)
        XCTAssertEqual(scan.step, .back)
        scan.add(image(width: 20, height: 20), for: scan.step)
        XCTAssertEqual(scan.step, .label)
        XCTAssertFalse(scan.isComplete)
        scan.add(image(width: 30, height: 30), for: scan.step)
        XCTAssertTrue(scan.isComplete)
        XCTAssertEqual(scan.orderedShots.map(\.kind), [.front, .back, .label])
        XCTAssertEqual(scan.orderedShots.map(\.image.size.width), [10, 20, 30], "upload order is front, back, label")
    }

    @MainActor
    func testSkippingBackStillUploadsFrontThenLabel() {
        let scan = ScanSession()
        scan.add(image(width: 10, height: 10), for: .front)
        scan.skip(.back)
        XCTAssertEqual(scan.step, .label)
        scan.add(image(width: 30, height: 30), for: .label)
        XCTAssertTrue(scan.isComplete)
        XCTAssertEqual(scan.orderedShots.map(\.kind), [.front, .label])
    }

    @MainActor
    func testFrontIsRequiredAndCannotBeSkipped() {
        let scan = ScanSession()
        scan.skip(.front)
        XCTAssertFalse(scan.skipped.contains(.front))
        scan.skip(.back)
        scan.skip(.label)
        XCTAssertFalse(scan.isComplete, "no front photo yet")
    }

    @MainActor
    func testFrontAloneIsCompleteOnceBackAndLabelAreSkipped() {
        let scan = ScanSession()
        scan.add(image(width: 10, height: 10), for: .front)
        scan.skip(.back)
        scan.skip(.label)
        XCTAssertTrue(scan.isComplete)
        XCTAssertEqual(scan.orderedShots.map(\.kind), [.front])
    }

    @MainActor
    func testRetakeReplacesTheShotInPlaceWithoutReordering() {
        let scan = ScanSession()
        scan.add(image(width: 10, height: 10), for: .front)
        scan.add(image(width: 20, height: 20), for: .back)
        scan.add(image(width: 30, height: 30), for: .label)
        scan.retake(.back)
        XCTAssertEqual(scan.step, .back)
        scan.add(image(width: 99, height: 99), for: scan.step)
        XCTAssertEqual(scan.orderedShots.map(\.image.size.width), [10, 99, 30])
    }

    @MainActor
    func testLibraryPicksFillTheCurrentStepJustLikeCameraShots() {
        // The photo-library button and the shutter both end in `scan.add(_, for: scan.step)`.
        let scan = ScanSession()
        for width in [11.0, 22.0, 33.0] { scan.add(image(width: width, height: width), for: scan.step) }
        XCTAssertEqual(scan.orderedShots.map(\.kind), [.front, .back, .label])
        XCTAssertTrue(scan.isComplete)
    }

    // MARK: Resizing and compression

    func testLargePhotoIsResizedToAtMost1600PxAndEncodedAsJPEG() throws {
        let big = image(width: 4032, height: 3024)
        let data = ImageProcessing.jpeg(big)
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF], "JPEG magic bytes")
        let size = try XCTUnwrap(pixelSize(of: data))
        XCTAssertEqual(max(size.width, size.height), 1600, accuracy: 1)
        XCTAssertEqual(size.width / size.height, 4032.0 / 3024.0, accuracy: 0.01, "aspect ratio is kept")
        XCTAssertLessThan(data.count, 5 * 1024 * 1024, "well under the server's 5 MB limit")
    }

    func testSmallPhotoIsNotUpscaled() throws {
        let data = ImageProcessing.jpeg(image(width: 800, height: 600))
        let size = try XCTUnwrap(pixelSize(of: data))
        XCTAssertEqual(size.width, 800, accuracy: 1)
    }

    func testRetinaScaleIsCountedInPixels() throws {
        // A 3x image of 1000x1000 points is 3000x3000 pixels and must still end at 1600 px.
        let data = ImageProcessing.jpeg(image(width: 1000, height: 1000, scale: 3))
        let size = try XCTUnwrap(pixelSize(of: data))
        XCTAssertEqual(max(size.width, size.height), 1600, accuracy: 1)
    }

    func testPNGInputBecomesJPEG() throws {
        let png = try XCTUnwrap(image(width: 300, height: 200).pngData())
        XCTAssertEqual(Array(png.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        let data = ImageProcessing.jpeg(try XCTUnwrap(UIImage(data: png)))
        XCTAssertEqual(Array(data.prefix(3)), [0xFF, 0xD8, 0xFF], "the server only accepts JPEG")
    }

    func testEXIFOrientationIsBakedIntoThePixels() throws {
        // A phone in portrait stores a landscape bitmap tagged `.right`. After processing it must be upright (portrait).
        let landscape = try XCTUnwrap(image(width: 400, height: 300).cgImage)
        let tagged = UIImage(cgImage: landscape, scale: 1, orientation: .right)
        XCTAssertEqual(tagged.size, CGSize(width: 300, height: 400))
        let size = try XCTUnwrap(pixelSize(of: ImageProcessing.jpeg(tagged)))
        XCTAssertEqual(size.width, 300, accuracy: 1)
        XCTAssertEqual(size.height, 400, accuracy: 1)
    }

    // MARK: Apple Vision on device

    private func tagPhoto() -> UIImage {
        let size = CGSize(width: 900, height: 500)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 110, weight: .bold), .foregroundColor: UIColor.black, .paragraphStyle: style]
            "LEVI'S\nSIZE MEDIUM".draw(in: CGRect(x: 0, y: 70, width: 900, height: 400), withAttributes: attributes)
        }
    }

    /// A stalled Vision call must never block a scan: the labeler gives up at its deadline and still returns.
    func testLabelerAlwaysReturnsWithinItsDeadline() async {
        let start = Date()
        _ = await OnDeviceLabeler.labels(for: tagPhoto(), readText: true, deadline: 3)
        XCTAssertLessThan(Date().timeIntervalSince(start), 6, "labels() must return by its deadline even if Vision hangs")
    }

    func testOCRReadsTextOffATagPhoto() async throws {
        let labels = await OnDeviceLabeler.labels(for: tagPhoto(), readText: true, deadline: 20)
        print("OCR labels:", labels)
        let joined = labels.joined(separator: " ").uppercased()
        #if targetEnvironment(simulator)
        // The Simulator's Vision stack can return no text at all. Only assert content when it did read something.
        try XCTSkipIf(!joined.contains("LEVI") && !joined.contains("SIZE") && !joined.contains("MEDIUM"),
                      "Vision returned no text in the Simulator (\(labels)); verify OCR on a device")
        #endif
        XCTAssertTrue(joined.contains("LEVI"), "OCR should read the brand, got: \(labels)")
        XCTAssertTrue(joined.contains("MEDIUM") || joined.contains("SIZE"), "OCR should read the size line, got: \(labels)")
        XCTAssertFalse(labels.contains { $0.contains(",") }, "commas separate labels in the form field")
    }

    func testClassificationOnlyReturnsAtMostFiveCleanLabels() async {
        let labels = await OnDeviceLabeler.labels(for: image(width: 600, height: 600, color: .red), readText: false)
        XCTAssertLessThanOrEqual(labels.count, 5)
        XCTAssertFalse(labels.contains { $0.contains(",") || $0.contains("_") })
    }

    // MARK: Request formatting for POST /scan

    func testScanRequestBodyMatchesTheContract() throws {
        let front = Data([0xFF, 0xD8, 0xFF, 0x01]), back = Data([0xFF, 0xD8, 0xFF, 0x02]), label = Data([0xFF, 0xD8, 0xFF, 0x03])
        let form = LiveAPIClient.scanForm(photos: [(front, .front), (back, .back), (label, .label)],
                                          labels: ["denim jacket", "LEVI'S", "SIZE M"])
        XCTAssertTrue(form.contentType.hasPrefix("multipart/form-data; boundary="))
        let body = form.finalized()
        let text = String(decoding: body, as: UTF8.self)
        func count(_ needle: String) -> Int { text.components(separatedBy: needle).count - 1 }

        XCTAssertEqual(count("name=\"photos\"; filename=\""), 3, "one `photos` part per image")
        XCTAssertEqual(count("Content-Type: image/jpeg"), 3)
        // Photos appear in order front, back, label.
        let marks = [front, back, label].compactMap { body.range(of: $0)?.lowerBound }
        XCTAssertEqual(marks.count, 3)
        XCTAssertEqual(marks, marks.sorted(), "photo parts are in front, back, label order")
        XCTAssertTrue(text.contains("name=\"kinds\"\r\n\r\nfront,back,label\r\n"))
        XCTAssertTrue(text.contains("name=\"labels\"\r\n\r\ndenim jacket,LEVI'S,SIZE M\r\n"))
        XCTAssertTrue(text.hasSuffix("--\r\n"), "the body ends with the closing boundary")
        let boundary = String(form.contentType.dropFirst("multipart/form-data; boundary=".count))
        XCTAssertEqual(count("--\(boundary)\r\n"), 5, "3 photos + kinds + labels")
    }

    func testScanRequestOmitsLabelsWhenThereAreNone() {
        let form = LiveAPIClient.scanForm(photos: [(Data([0xFF, 0xD8, 0xFF]), .front)], labels: [])
        let text = String(decoding: form.finalized(), as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"kinds\"\r\n\r\nfront\r\n"))
        XCTAssertFalse(text.contains("name=\"labels\""))
    }

    func testSkippedBackSendsTwoKindsForTwoPhotos() {
        let form = LiveAPIClient.scanForm(photos: [(Data([1]), .front), (Data([2]), .label)], labels: [])
        XCTAssertTrue(String(decoding: form.finalized(), as: UTF8.self).contains("front,label"),
                      "the server requires one kind per photo")
    }

    // MARK: Mock ↔ live switching and notification freshness

    func testClientFollowsTheMockLiveSwitchWithoutCodeChanges() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "useMocks") }
        APIConfig.setUseMocks(true)
        XCTAssertTrue(API.client is MockAPIClient)
        APIConfig.setUseMocks(false)
        XCTAssertTrue(API.client is LiveAPIClient)
        APIConfig.setUseMocks(true)
        XCTAssertTrue(API.client is MockAPIClient)
    }

    func testMockAndLiveSessionsKeepSeparateTokens() {
        defer { UserDefaults.standard.removeObject(forKey: "useMocks"); APIConfig.setUseMocks(true); AuthToken.set(nil); APIConfig.setUseMocks(false); AuthToken.set(nil) }
        APIConfig.setUseMocks(true)
        AuthToken.set("mock-3")
        APIConfig.setUseMocks(false)
        XCTAssertNil(AuthToken.current, "a mock token must never be sent to the real server")
        AuthToken.set("live-token")
        APIConfig.setUseMocks(true)
        XCTAssertEqual(AuthToken.current, "mock-3")
    }

    func testCollapsedNewMessageNotificationCountsAsFreshWhenItsDateMoves() {
        func note(_ id: Int, _ seconds: TimeInterval) -> AppNotification {
            AppNotification(id: id, type: .newMessage, title: "Sam sent you a message", body: "hi", requestId: 9, listingId: 42,
                            read: false, createdAt: Date(timeIntervalSince1970: 1_800_000_000 + seconds))
        }
        let seen = [7: note(7, 0).createdAt]
        XCTAssertTrue(NotificationStore.freshItems(in: [note(7, 0)], previous: seen).isEmpty, "unchanged row is not fresh")
        XCTAssertEqual(NotificationStore.freshItems(in: [note(7, 30)], previous: seen).map(\.id), [7], "same id, newer created_at")
        XCTAssertEqual(NotificationStore.freshItems(in: [note(8, 0)], previous: seen).map(\.id), [8], "a brand-new id")
    }

    // MARK: Draft handling

    func testRetryKeepsWhatTheUserAlreadyTyped() {
        var form = ListingFormState()
        form.title = "My own title"
        form.condition = .worn
        form.apply(ScanDraft(title: "AI title", category: .tops, size: "M", color: "Blue", brand: "Levi's",
                             condition: .good, description: "AI text", tags: ["denim"]), onlyBlank: true)
        XCTAssertEqual(form.title, "My own title")
        XCTAssertEqual(form.condition, .worn)
        XCTAssertEqual(form.category, .tops, "blank fields still take the AI's value")
        XCTAssertEqual(form.brand, "Levi's")
        XCTAssertEqual(form.tags, ["denim"])
    }

    func testAnAllNullDraftNeverErasesManualEntry() {
        var form = ListingFormState()
        form.title = "Typed by hand"
        form.category = .shoes
        form.apply(.empty, onlyBlank: true)
        XCTAssertEqual(form.title, "Typed by hand")
        XCTAssertEqual(form.category, .shoes)
    }
}
