import XCTest

/// Walks the demo journey on mock data and saves a screenshot at each stop.
final class LoopUITests: XCTestCase {
    let shotDir = "/private/tmp/claude-505/-Users-Yusung-Hwang-Desktop-loop/e029d426-1247-48a5-bce3-dc7affaff7f2/scratchpad/shots"
    var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        // System permission alerts (camera) get allowed whenever they appear.
        addUIInterruptionMonitor(withDescription: "Permissions") { alert in
            for label in ["Allow", "OK", "Allow While Using App"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }
        app = XCUIApplication()
        app.launchArguments = ["-useMocks", "YES", "-resetSession", "YES", "-uiTesting", "YES"]
        app.launch()
    }

    // MARK: Helpers

    func shot(_ name: String) {
        Thread.sleep(forTimeInterval: 0.7)
        let image = XCUIScreen.main.screenshot()
        try? FileManager.default.createDirectory(atPath: shotDir, withIntermediateDirectories: true)
        try? image.pngRepresentation.write(to: URL(fileURLWithPath: "\(shotDir)/\(name).png"))
        let attachment = XCTAttachment(screenshot: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func button(containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    func tab(_ name: String) {
        let item = app.tabBars.buttons[name]
        if !item.waitForExistence(timeout: 5) { shot("fail-tab-\(name)") }
        XCTAssertTrue(item.exists, "tab \(name)")
        item.tap()
    }

    func signIn(as name: String) {
        let chip = app.buttons[name]
        XCTAssertTrue(chip.waitForExistence(timeout: 10), "demo chip \(name)")
        chip.tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 10), "feed after sign-in")
    }

    func back() {
        app.navigationBars.buttons.firstMatch.tap()
    }

    // MARK: Tests

    /// Read-only walk through the live server as the seeded demo account Jordan (nothing is created or changed).
    /// Opt in with `TEST_RUNNER_LOOP_LIVE=1 xcodebuild test ...`.
    func testLiveServerReadOnly() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOOP_LIVE"] == "1", "set TEST_RUNNER_LOOP_LIVE=1 to hit the live server")
        app.terminate()
        app.launchArguments = ["-useMocks", "NO", "-resetSession", "YES", "-uiTesting", "YES"]
        app.launch()
        signIn(as: "Jordan")
        let firstCard = app.buttons.matching(identifier: "listingCard").firstMatch
        XCTAssertTrue(firstCard.waitForExistence(timeout: 15), "live feed loads listings")
        Thread.sleep(forTimeInterval: 4)   // photos
        shot("L1-feed-live")
        firstCard.tap()
        XCTAssertTrue(app.buttons["Back"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 3)
        shot("L2-detail-live")
        app.buttons["Back"].tap()
        tab("Requests")
        Thread.sleep(forTimeInterval: 3)
        shot("L3-requests-live")
        tab("Profile")
        XCTAssertTrue(app.staticTexts["Badges"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 3)
        shot("L4-profile-live")
        button(containing: "Your impact").tap()
        XCTAssertTrue(app.staticTexts["Dorm leaderboard"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 2)
        shot("L5-impact-live")
    }

    func testSignInRejectsNonEdu() {
        XCTAssertTrue(app.buttons["Jordan"].waitForExistence(timeout: 10))
        shot("01-signin")
        let field = app.textFields.firstMatch
        field.tap()
        field.typeText("nobody@gmail.com")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.staticTexts["Use your college .edu email address."].waitForExistence(timeout: 3))
        shot("01b-signin-error")
    }

    func testNewUserProfileSetup() {
        let field = app.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        field.typeText("casey.lin@vanderbilt.edu")
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.navigationBars["Set up your profile"].waitForExistence(timeout: 10))
        shot("00-profile-setup")
        let name = app.textFields["Name"]
        name.tap()
        name.typeText("Casey Lin")
        app.buttons["Done"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 10))
    }

    /// Jordan: scan → review → post → detail → save → requests → chat → complete → impact.
    func testJordanJourney() {
        signIn(as: "Jordan")
        XCTAssertTrue(app.staticTexts["Levi's denim trucker jacket"].waitForExistence(timeout: 10))
        shot("02-feed")

        // Scan with sample photos, review, post.
        app.buttons["Scan an item"].tap()
        let sample = app.buttons["sampleBtn"]
        XCTAssertTrue(sample.waitForExistence(timeout: 8))
        shot("04-scan")
        sample.tap()
        XCTAssertTrue(app.staticTexts["Reading your photos…"].waitForExistence(timeout: 5))
        shot("05a-review-loading")
        XCTAssertTrue(app.staticTexts["Filled in by AI. Check before posting."].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.0)   // let the skeleton → fields cross-fade finish
        let swap = app.segmentedControls.firstMatch.buttons["Swap"]
        for _ in 0..<3 where !swap.isSelected { swap.tap(); Thread.sleep(forTimeInterval: 0.4) }
        XCTAssertTrue(swap.isSelected, "Swap is selected")
        let picker = app.buttons["meetupPicker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        picker.tap()
        app.buttons["Commons Center"].firstMatch.tap()
        shot("05b-review-filled")
        let post = app.buttons["Post"]
        XCTAssertTrue(post.isEnabled, "Post enabled once required fields are set")
        post.tap()
        XCTAssertTrue(app.tabBars.buttons["Feed"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        shot("06-feed-after-post")

        // Item detail (my own listing).
        button(containing: "Carhartt").tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "owner sees Edit")
        shot("03-detail-own")
        back()

        // Save an item from someone else, find it in Saved.
        let heart = app.buttons["Save"].firstMatch
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        heart.tap()
        tab("Saved")
        XCTAssertTrue(button(containing: "Levi").waitForExistence(timeout: 5), "saved item shows in Saved")
        shot("07a-saved")

        // Requests: accept Sam's incoming request, then open my outgoing chat and finish the exchange.
        tab("Requests")
        XCTAssertTrue(app.buttons["Accept"].firstMatch.waitForExistence(timeout: 8))
        shot("07-requests")
        app.buttons["Accept"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1.0)
        app.buttons["Outgoing"].tap()
        let thread = button(containing: "Patagonia")
        XCTAssertTrue(thread.waitForExistence(timeout: 5))
        thread.tap()
        XCTAssertTrue(app.buttons["Mark exchange done"].waitForExistence(timeout: 8))
        let composer = app.textViews["composer"].exists ? app.textViews["composer"] : app.textFields["composer"]
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        composer.tap()
        composer.typeText("Commons at 4?")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["Commons at 4?"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 3.5)   // canned reply arrives
        app.swipeDown(velocity: .slow)
        shot("08-chat")
        app.buttons["Mark exchange done"].tap()
        app.buttons["Mark as done"].tap()
        XCTAssertTrue(app.staticTexts["Exchange complete"].waitForExistence(timeout: 8))
        Thread.sleep(forTimeInterval: 4)   // count-up and badge flip
        shot("10-complete")
        XCTAssertTrue(app.staticTexts["First Swap"].exists, "First Swap badge unlocked")
        app.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        back()   // thread → Requests (tab bar is hidden inside the thread)

        // Profile: impact strip and badge update.
        tab("Profile")
        XCTAssertTrue(app.staticTexts["Badges"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        shot("09-profile")
        button(containing: "Your impact").tap()
        XCTAssertTrue(app.staticTexts["Dorm leaderboard"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        shot("09b-impact")
    }

    /// Sam: request an item → the owner accepts → banner → chat.
    func testSamRequestJourney() {
        signIn(as: "Sam")
        XCTAssertTrue(app.staticTexts["Vintage Vanderbilt crewneck"].waitForExistence(timeout: 10))
        button(containing: "Vintage").tap()
        let request = app.buttons["Request"]
        XCTAssertTrue(request.waitForExistence(timeout: 5))
        shot("03-detail")
        request.tap()
        let send = app.buttons["Send request"]
        XCTAssertTrue(send.waitForExistence(timeout: 5))
        shot("03b-request-sheet")
        send.tap()
        XCTAssertTrue(app.buttons["Requested"].waitForExistence(timeout: 5), "button becomes Requested")
        // The mock owner accepts after about 4 seconds; the banner follows on the next poll.
        let banner = app.descendants(matching: .any)["inAppBanner"]
        if !banner.waitForExistence(timeout: 25) { shot("fail-banner") }
        XCTAssertTrue(banner.exists, "accepted banner")
        shot("11-banner")
        banner.tap()
        XCTAssertTrue(app.buttons["Mark exchange done"].waitForExistence(timeout: 8), "banner opens the thread")
    }

    /// Filters, search with no results, notifications, Style it, report, and Edit listing.
    func testSecondaryScreens() {
        signIn(as: "Jordan")
        XCTAssertTrue(app.staticTexts["Vintage Vanderbilt crewneck"].waitForExistence(timeout: 10))

        // Filters sheet → category → results narrow down.
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.navigationBars["Filters"].waitForExistence(timeout: 5))
        shot("12-filters")
        app.buttons["Outerwear"].tap()
        app.buttons["Show results"].tap()
        XCTAssertTrue(app.buttons["Filters · 1"].waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertFalse(app.staticTexts["Vintage Vanderbilt crewneck"].exists, "crewneck is hidden by the Outerwear filter")
        shot("12b-filtered")

        // Search with no results shows the empty state and a way out.
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No matches"].waitForExistence(timeout: 5))
        shot("12c-no-results")
        app.buttons["Clear filters"].tap()
        if app.buttons["Cancel"].exists { app.buttons["Cancel"].tap() }
        XCTAssertTrue(app.staticTexts["Vintage Vanderbilt crewneck"].waitForExistence(timeout: 5))

        // Notifications list.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 5))
        shot("13-notifications")
        back()

        // Item detail: Style it sheet, then Report.
        button(containing: "Vintage").tap()
        let style = app.buttons["Style it"]
        for _ in 0..<3 where !style.isHittable { app.swipeUp() }
        style.tap()
        XCTAssertTrue(app.staticTexts["Weekend layers"].waitForExistence(timeout: 8))
        shot("14-style-it")
        app.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 1.0)
        shot("14a-after-style")
        let more = app.buttons["More options"]
        if more.isHittable { more.tap() } else { more.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
        app.buttons["Report"].tap()
        shot("14b-report")
        app.buttons["Spam"].tap()
        XCTAssertTrue(app.staticTexts["Thanks, we'll take a look."].waitForExistence(timeout: 5))
        back()

        // Edit my own listing.
        let adidas = button(containing: "Adidas")
        for _ in 0..<8 where !adidas.exists || !adidas.isHittable { app.swipeUp() }
        adidas.tap()
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.navigationBars["Edit listing"].waitForExistence(timeout: 5))
        shot("15-edit")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.buttons["Edit"].waitForExistence(timeout: 5), "back on detail after saving")
    }

    func testEmptyStates() {
        signIn(as: "Riley")
        tab("Saved")
        XCTAssertTrue(app.staticTexts["Nothing saved yet"].waitForExistence(timeout: 5))
        shot("16-saved-empty")
        tab("Feed")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Notifications'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["No notifications"].waitForExistence(timeout: 5))
        shot("16b-notifications-empty")
    }
}
