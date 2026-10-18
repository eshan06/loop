import XCTest

/// The coordinated live end-to-end run against the real server (docs/API.md), one phase per test.
/// Opt in with `TEST_RUNNER_LOOP_E2E=<phase>`; every phase is skipped otherwise. This creates, changes and
/// completes real data for the agreed accounts (Jordan owns the listing, Sam requests it), so only run it
/// after the server lane has reseeded and both developers have agreed.
///
/// Phases, in order: A Jordan scans and posts, B Sam requests, C Jordan accepts and writes, D Sam reads and
/// replies, E Jordan completes, F Sam sees it completed. Photos come from the Simulator's library: the last three
/// items are used as front, back, label (`xcrun simctl addmedia`).
final class LiveE2ETests: XCTestCase {
    let dir = "/private/tmp/claude-505/-Users-Yusung-Hwang-Desktop-loop/e029d426-1247-48a5-bce3-dc7affaff7f2/scratchpad/e2e"
    var app: XCUIApplication!
    var phase = ""

    override func setUp() {
        continueAfterFailure = false
    }

    private func start(_ name: String, freshSession: Bool = false) throws {
        phase = name
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOOP_E2E"] == name, "set TEST_RUNNER_LOOP_E2E=\(name)")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchArguments = ["-useMocks", "NO", "-uiTesting", "YES"] + (freshSession ? ["-resetSession", "YES"] : [])
        app.launch()
    }

    private func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.8)
        let image = XCUIScreen.main.screenshot()
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(dir)/\(phase)-\(name).png"))
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = "\(phase)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ line: String) {
        print("E2E[\(phase)] \(line)")
        let path = "\(dir)/phase-\(phase).txt"
        let existing = (try? String(contentsOfFile: path)) ?? ""
        try? (existing + line + "\n").write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func signIn(as name: String) {
        if app.tabBars.buttons["Feed"].waitForExistence(timeout: 6) { note("already signed in"); return }
        let chip = app.buttons[name]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "demo chip \(name)")
        XCTAssertTrue(app.segmentedControls["serverMode"].buttons["Live server"].isSelected, "Live server mode")
        chip.tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 15), "feed after sign-in")
    }

    private func tab(_ name: String) {
        let item = app.tabBars.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 8), "tab \(name)")
        item.tap()
    }

    private func openThread(role: String, containing title: String) {
        tab("Requests")
        let seg = app.buttons[role]
        XCTAssertTrue(seg.waitForExistence(timeout: 8))
        seg.tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "request row for \(title)")
        row.tap()
        XCTAssertTrue(app.buttons["Mark exchange done"].waitForExistence(timeout: 12), "thread opened")
    }

    private func send(_ text: String) {
        let composer = app.textViews["composer"].exists ? app.textViews["composer"] : app.textFields["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText(text)
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 10), "message shows after send")
    }

    private var listingTitle: String {
        (try? String(contentsOfFile: "\(dir)/listing-title.txt").trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
    }

    // MARK: Phases

    /// A. Jordan: scan three library photos with the real AI, review, post.
    func testA_JordanScansAndPosts() throws {
        try start("A", freshSession: true)
        signIn(as: "Jordan")
        XCTAssertTrue(app.buttons.matching(identifier: "listingCard").firstMatch.waitForExistence(timeout: 15))
        shot("feed-before")
        app.buttons["Scan an item"].tap()
        XCTAssertTrue(app.buttons["sampleBtn"].waitForExistence(timeout: 8), "no camera in the Simulator")
        for (index, step) in ["Front", "Back", "Label"].enumerated() {
            XCTAssertTrue(app.staticTexts[step].waitForExistence(timeout: 5), "step \(step) is showing")
            app.buttons["Choose from library"].tap()
            let photos = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'"))
            XCTAssertTrue(photos.firstMatch.waitForExistence(timeout: 10), "picker has photos")
            Thread.sleep(forTimeInterval: 1.0)
            // The grid is newest first, and the three photos added last are ours: label, back, front.
            if step == "Front" { shot("picker"); note("picker shows \(photos.count) photos; using the newest three") }
            photos.element(boundBy: 2 - index).tap()
            Thread.sleep(forTimeInterval: 2.0)
        }
        let scanStart = Date()
        XCTAssertTrue(app.staticTexts["Reading your photos…"].waitForExistence(timeout: 8), "Review opened with skeletons")
        shot("review-loading")
        let filled = app.staticTexts["Filled in by AI. Check before posting."]
        let failed = app.buttons["Try again"]
        let deadline = Date().addingTimeInterval(45)
        while !filled.exists && !failed.exists && Date() < deadline { Thread.sleep(forTimeInterval: 0.25) }
        note(String(format: "scan returned in %.1f s (app side, includes photo encode and upload)", Date().timeIntervalSince(scanStart)))
        note(filled.exists ? "app shows 'Filled in by AI' banner" : "app shows the failure state (Try again)")
        XCTAssertTrue(filled.exists, "the scan filled in the draft")
        Thread.sleep(forTimeInterval: 1.2)
        let title = app.textFields["Title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let titleValue = (title.value as? String) ?? ""
        note("title field: \(titleValue)")
        for _ in 0..<4 where !app.textFields["Brand"].exists { app.swipeUp() }
        for field in ["Brand", "Color"] where app.textFields[field].exists {
            note("\(field.lowercased()) field: \((app.textFields[field].value as? String) ?? "?")")
        }
        shot("review-details")
        for _ in 0..<4 where !app.buttons["categoryPicker"].isHittable { app.swipeDown() }
        note("category: \(app.buttons["categoryPicker"].value ?? app.buttons["categoryPicker"].label)")
        try? titleValue.write(toFile: "\(dir)/listing-title.txt", atomically: true, encoding: .utf8)
        for _ in 0..<5 { app.swipeDown() }
        shot("review-filled")

        let swap = app.segmentedControls.firstMatch.buttons["Swap"]
        for _ in 0..<3 where !swap.isSelected { swap.tap(); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(swap.isSelected)
        let picker = app.buttons["meetupPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        app.buttons["Commons Center"].firstMatch.tap()
        shot("review-ready")
        let post = app.buttons["Post"]
        XCTAssertTrue(post.isEnabled)
        post.tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 20), "back on the feed after posting")
        XCTAssertTrue(app.staticTexts["Just posted"].waitForExistence(timeout: 10), "new card is highlighted")
        shot("feed-after-post")
        note("posted")
    }

    /// B. Sam: find the new listing by search and request it.
    func testB_SamRequests() throws {
        try start("B", freshSession: true)
        signIn(as: "Sam")
        XCTAssertTrue(app.buttons.matching(identifier: "listingCard").firstMatch.waitForExistence(timeout: 15))
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("jacket\n")
        Thread.sleep(forTimeInterval: 3)
        shot("search-jacket")
        let first = app.buttons.matching(identifier: "listingCard").firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 10), "search finds jackets")
        note("top search result: \(first.label)")
        first.tap()
        let request = app.buttons["Request"]
        XCTAssertTrue(request.waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 2)
        shot("detail")
        request.tap()
        let sendButton = app.buttons["Send request"]
        XCTAssertTrue(sendButton.waitForExistence(timeout: 5))
        shot("request-sheet")
        sendButton.tap()
        XCTAssertTrue(app.buttons["Requested"].waitForExistence(timeout: 10), "button becomes Requested")
        shot("requested")
        note("requested")
    }

    /// C. Jordan: the request arrives, accept it, open the chat and write.
    func testC_JordanAcceptsAndWrites() throws {
        try start("C")
        signIn(as: "Jordan")
        tab("Requests")
        shot("requests-incoming")
        // Accepting a request auto-declines the others on that listing, so tap only the Accept button that sits
        // in the row of our jacket (the Accept closest below its title), never "the first one".
        let titleText = app.staticTexts.matching(NSPredicate(format: "label == %@", listingTitle)).firstMatch
        XCTAssertTrue(titleText.waitForExistence(timeout: 12), "Sam's request for the new jacket is listed")
        XCTAssertTrue(app.buttons["Accept"].firstMatch.waitForExistence(timeout: 5))
        let titleY = titleText.frame.minY
        let candidates = app.buttons.matching(identifier: "Accept").allElementsBoundByIndex
            .filter { $0.frame.minY > titleY && $0.frame.minY - titleY < 180 }
            .sorted { $0.frame.minY < $1.frame.minY }
        guard let accept = candidates.first else { return XCTFail("no Accept button in the jacket's row") }
        note("accepting the Accept button \(Int(accept.frame.minY - titleY)) pt below the title '\(listingTitle)'")
        accept.tap()
        Thread.sleep(forTimeInterval: 2)
        shot("accepted")
        let title = listingTitle
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", title)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), "accepted row")
        row.tap()
        XCTAssertTrue(app.buttons["Mark exchange done"].waitForExistence(timeout: 12))
        send("Hey Sam! Commons Center at 4 today works for me.")
        shot("chat")
        note("accepted and sent first message")
    }

    /// D. Sam: sees the accepted request and Jordan's message, replies.
    func testD_SamRepliesInChat() throws {
        try start("D")
        signIn(as: "Sam")
        tab("Requests")
        app.buttons["Outgoing"].tap()
        shot("requests-outgoing")
        openThread(role: "Outgoing", containing: listingTitle)
        XCTAssertTrue(app.staticTexts["Hey Sam! Commons Center at 4 today works for me."].waitForExistence(timeout: 10), "Sam sees Jordan's message")
        shot("chat-before-reply")
        send("Perfect, see you there!")
        shot("chat-after-reply")
        note("saw Jordan's message and replied")
    }

    /// E. Jordan: sees Sam's reply, marks the exchange done.
    func testE_JordanCompletes() throws {
        try start("E")
        signIn(as: "Jordan")
        openThread(role: "Incoming", containing: listingTitle)
        XCTAssertTrue(app.staticTexts["Perfect, see you there!"].waitForExistence(timeout: 12), "Jordan sees Sam's reply")
        shot("chat-with-reply")
        app.buttons["Mark exchange done"].tap()
        app.buttons["Mark as done"].tap()
        XCTAssertTrue(app.staticTexts["Exchange complete"].waitForExistence(timeout: 12), "celebration")
        Thread.sleep(forTimeInterval: 4)
        shot("complete")
        note("celebration badge text present: First Swap=\(app.staticTexts["First Swap"].exists)")
        app.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 1.5)
        note("completed")
    }

    /// F. Sam: the completed exchange in the Requests tab and its thread; the profile shows the new badge.
    func testF_SamSeesCompletion() throws {
        try start("F")
        signIn(as: "Sam")
        Thread.sleep(forTimeInterval: 3)
        shot("feed")
        tab("Requests")
        app.buttons["Outgoing"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", listingTitle)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 12), "Sam's request row")
        note("outgoing row label: \(row.label)")
        shot("requests-outgoing")
        row.tap()
        Thread.sleep(forTimeInterval: 4)
        note("thread shows the Mark exchange done button: \(app.buttons["Mark exchange done"].exists)")
        note("thread shows Exchange complete: \(app.staticTexts["Exchange complete"].exists)")
        note("thread shows Jordan's message: \(app.staticTexts["Hey Sam! Commons Center at 4 today works for me."].exists)")
        shot("thread-completed")
        app.navigationBars.buttons.firstMatch.tap()
        tab("Profile")
        Thread.sleep(forTimeInterval: 3)
        shot("profile")
        note("profile shows First Swap: \(app.staticTexts["First Swap"].exists)")
    }
}
