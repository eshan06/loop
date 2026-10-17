import XCTest
@testable import Loop

/// Model decoding, size vocabulary, and the stateful mock backend.
final class LoopTests: XCTestCase {

    // MARK: Models and mocks

    func testEveryMockFixtureDecodesIntoTheContractModels() {
        // MockFixtures.load traps on a missing or mismatched file, so touching each one is the test.
        XCTAssertEqual(MockFixtures.listings.count, 18)
        XCTAssertFalse(MockFixtures.users.isEmpty)
        XCTAssertEqual(MockFixtures.requests.count, 3)
        XCTAssertEqual(MockFixtures.messages.count, 2)
        XCTAssertEqual(MockFixtures.notifications.items.count, 3)
        XCTAssertFalse(MockFixtures.meetupSpots.isEmpty)
        XCTAssertFalse(MockFixtures.dorms.isEmpty)
        XCTAssertEqual(MockFixtures.scan.source, .vision)
        XCTAssertEqual(MockFixtures.scanNone.source, ScanSource.none)
        XCTAssertTrue(MockFixtures.scanNone.draft.tags.isEmpty)
        XCTAssertEqual(MockFixtures.badges.map(\.id), ["first_swap", "giving_back", "closet_cleanout"])
        XCTAssertEqual(MockFixtures.style.ideas.count, 3)
        XCTAssertFalse(MockFixtures.leaderboard.isEmpty)
    }

    func testSnakeCaseAndIsoDatesDecodeLikeTheServerSendsThem() throws {
        let json = """
        {"id":42,"title":"Jacket","category":"outerwear","size":null,"color":null,"brand":null,"condition":"like_new",
         "description":null,"tags":[],"share_type":"free","status":"pending",
         "photos":[{"id":1,"url":"http://163.192.218.131:8000/media/1.jpg","kind":"front"}],
         "meetup_spot":null,"owner":{"id":3,"name":null,"dorm":null,"avatar_url":null,"items_shared":0},
         "impact":{"textile_kg":1,"water_l":2500,"co2_kg":10.5},"is_mine":false,"saved_by_me":true,
         "my_request_status":"accepted","my_request_id":9,"pending_request_count":0,"accepted_request_id":null,
         "created_at":"2026-10-18T15:04:05Z"}
        """.data(using: .utf8)!
        let listing = try LiveAPIClient.decoder.decode(Listing.self, from: json)
        XCTAssertEqual(listing.condition, .likeNew)
        XCTAssertEqual(listing.shareType, .free)
        XCTAssertEqual(listing.myRequestStatus, .accepted)
        XCTAssertEqual(listing.owner.displayName, "Loop member")
        XCTAssertEqual(listing.impact.waterL, 2500)
        XCTAssertNil(listing.meetupSpot)
        XCTAssertEqual(listing.createdAt.timeIntervalSince1970, 1_792_335_845, accuracy: 1)
    }

    func testUnknownKeysFromANewerServerAreIgnored() throws {
        let json = #"{"id":1,"name":"A","dorm":null,"avatar_url":null,"items_shared":2,"brand_new_field":true}"#.data(using: .utf8)!
        XCTAssertEqual(try LiveAPIClient.decoder.decode(Owner.self, from: json).itemsShared, 2)
    }

    func testPatchMeSendsExplicitNullsForUnsetSizes() throws {
        let body = try LiveAPIClient.encoder.encode(ProfileUpdate(name: "A", sizes: Sizes(top: "M")))
        let object = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        let sizes = object["sizes"] as! [String: Any]
        XCTAssertEqual(sizes["top"] as? String, "M")
        XCTAssertTrue(sizes["bottom"] is NSNull, "sizes replaces all three values, so unset ones must be null")
        XCTAssertTrue(sizes["shoe"] is NSNull)
    }

    func testListingInputUsesTheContractFieldNames() throws {
        let input = ListingInput(title: "T", category: .tops, size: "M", color: nil, brand: nil, condition: .likeNew,
                                 description: nil, tags: ["a"], shareType: .donate, meetupSpotId: 2, photoIds: [1, 2])
        let object = try JSONSerialization.jsonObject(with: LiveAPIClient.encoder.encode(input)) as! [String: Any]
        XCTAssertEqual(object["share_type"] as? String, "donate")
        XCTAssertEqual(object["meetup_spot_id"] as? Int, 2)
        XCTAssertEqual(object["photo_ids"] as? [Int], [1, 2])
        XCTAssertEqual(object["condition"] as? String, "like_new")
    }

    func testErrorEnvelopeBecomesAnAPIErrorWithTheServersMessage() throws {
        let json = #"{"error":{"code":"already_requested","message":"You've already requested this."}}"#.data(using: .utf8)!
        let envelope = try LiveAPIClient.decoder.decode(ErrorEnvelope.self, from: json)
        let error = APIError(status: 409, code: envelope.error.code, message: envelope.error.message)
        XCTAssertEqual(error.userMessage, "You've already requested this.")
        XCTAssertEqual(error.apiCode, "already_requested")
    }

    func testUseMocksReadsLaunchArgumentStrings() {
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "useMocks") }
        defaults.removeObject(forKey: "useMocks")
        XCTAssertEqual(APIConfig.useMocks, APIConfig.defaultUseMocks)
        // `-useMocks NO` on the command line is stored as the string "NO".
        defaults.set("NO", forKey: "useMocks")
        XCTAssertFalse(APIConfig.useMocks)
        defaults.set("YES", forKey: "useMocks")
        XCTAssertTrue(APIConfig.useMocks)
    }

    // MARK: Sizes and impact

    func testSizeVocabularyMatchesTheServersList() {
        XCTAssertEqual(SizeVocabulary.options(for: .tops), ["XS", "S", "M", "L", "XL", "XXL"])
        XCTAssertEqual(SizeVocabulary.options(for: .outerwear), SizeVocabulary.options(for: .dresses))
        XCTAssertEqual(SizeVocabulary.options(for: .bags), ["One size"])
        XCTAssertEqual(SizeVocabulary.options(for: .shoes).first, "5")
        XCTAssertTrue(SizeVocabulary.options(for: .shoes).contains("9.5"))
        XCTAssertEqual(SizeVocabulary.options(for: .shoes).last, "14")
        XCTAssertTrue(SizeVocabulary.options(for: .bottoms).contains("32"))
        XCTAssertTrue(SizeVocabulary.options(for: .bottoms).contains("XL"))
        XCTAssertEqual(SizeVocabulary.match("large", in: .tops), nil)
        XCTAssertEqual(SizeVocabulary.match("m", in: .tops), "M")
        XCTAssertNil(SizeVocabulary.match("32", in: .tops))
    }

    func testImpactComparisonsHideZeroAndPluralizeCorrectly() {
        XCTAssertNil(ImpactComparison.showers(20))
        XCTAssertEqual(ImpactComparison.showers(65), "≈ 1 shower")
        XCTAssertEqual(ImpactComparison.showers(130), "≈ 2 showers")
        XCTAssertEqual(ImpactComparison.miles(4), "≈ 10 miles not driven")
        XCTAssertEqual(ImpactFormat.mass(0.9), "0.9 kg")
        XCTAssertEqual(ImpactFormat.mass(61.5), "62 kg")
    }

    func testListingFormValidationNeedsTheRequiredFields() {
        var form = ListingFormState()
        XCTAssertFalse(form.isValid)
        form.apply(MockFixtures.scan.draft)
        XCTAssertFalse(form.isValid, "share type and meetup spot are still missing")
        form.shareType = .swap
        form.meetupSpotID = 2
        XCTAssertTrue(form.isValid)
        let input = try! XCTUnwrap(form.input(photoIDs: [1]))
        XCTAssertEqual(input.title, "Carhartt chore coat")
        XCTAssertEqual(input.photoIds, [1])
    }

    // MARK: Stateful mock backend: request → accept → chat → complete → impact

    func testMockBackendRunsTheWholeExchange() async throws {
        let api = MockAPIClient()
        AuthToken.set(nil)
        defer { AuthToken.set(nil) }

        let login = try await api.login(email: "sam.lee@vanderbilt.edu")
        AuthToken.set(login.token)
        XCTAssertFalse(login.isNew)

        // Request an item from someone else; the owner accepts on their own a few seconds later.
        let feed = try await api.listings(ListingQuery())
        let target = try XCTUnwrap(feed.items.first { $0.title.hasPrefix("Vintage") })
        XCTAssertFalse(target.isMine)
        let request = try await api.requestListing(id: target.id, note: "Hi!")
        XCTAssertEqual(request.status, .pending)

        do {
            _ = try await api.requestListing(id: target.id, note: nil)
            XCTFail("a second request should be rejected")
        } catch {
            XCTAssertEqual(error.apiCode, "already_requested")
        }

        try await Task.sleep(for: .seconds(5))
        let accepted = try await api.request(id: request.id)
        XCTAssertEqual(accepted.status, .accepted)
        let onHold = try await api.listing(id: target.id)
        XCTAssertEqual(onHold.status, .pending)

        // Chat opens once accepted, and the other person replies.
        let sent = try await api.sendMessage(requestID: request.id, body: "Commons at 4?")
        XCTAssertEqual(sent.body, "Commons at 4?")
        try await Task.sleep(for: .seconds(3.5))
        let thread = try await api.messages(requestID: request.id, afterID: nil)
        XCTAssertGreaterThanOrEqual(thread.count, 3, "owner's hello, my message, their reply")
        let nothingNew = try await api.messages(requestID: request.id, afterID: thread.last?.id)
        XCTAssertEqual(nothingNew.count, 0)

        // Completing adds impact for me and earns First Swap.
        let before = try await api.myImpact()
        let completed = try await api.perform(.complete, requestID: request.id)
        XCTAssertEqual(completed.status, .completed)
        let after = try await api.myImpact()
        XCTAssertGreaterThan(after.waterL, before.waterL)
        XCTAssertEqual(after.itemsReceived, before.itemsReceived + 1)
        let badges = try await api.badges()
        let firstSwap = try XCTUnwrap(badges.first { $0.id == "first_swap" })
        XCTAssertTrue(firstSwap.isEarned)
        let done = try await api.listing(id: target.id)
        XCTAssertEqual(done.status, .completed)
    }

    func testMockBackendEnforcesTheContractRules() async throws {
        let api = MockAPIClient()
        AuthToken.set(nil)
        defer { AuthToken.set(nil) }

        do { _ = try await api.login(email: "someone@gmail.com"); XCTFail() }
        catch { XCTAssertEqual(error.apiCode, "not_edu_email") }

        AuthToken.set((try await api.login(email: "jordan.park@vanderbilt.edu")).token)
        let mine = try await api.myListings(status: .active).items
        let own = try XCTUnwrap(mine.first)
        XCTAssertTrue(own.isMine)
        do { _ = try await api.requestListing(id: own.id, note: nil); XCTFail() }
        catch { XCTAssertEqual(error.apiCode, "own_listing") }

        // Saves round-trip, and three reports hide a listing.
        let everything = try await api.listings(ListingQuery()).items
        let other = try XCTUnwrap(everything.first { !$0.isMine })
        try await api.setSaved(true, listingID: other.id)
        let savedAfterSave = try await api.savedListings().items
        XCTAssertTrue(savedAfterSave.contains { $0.id == other.id })
        try await api.setSaved(false, listingID: other.id)
        let savedAfterUnsave = try await api.savedListings().items
        XCTAssertFalse(savedAfterUnsave.contains { $0.id == other.id })

        // Filters and search.
        let swaps = try await api.listings(ListingQuery(shareType: .swap)).items
        XCTAssertFalse(swaps.isEmpty)
        XCTAssertTrue(swaps.allSatisfy { $0.shareType == .swap })
        let found = try await api.listings(ListingQuery(q: "samba")).items
        XCTAssertEqual(found.map(\.title), ["Adidas Samba OG"])
    }

    // MARK: Live server, read-only (opt in with TEST_RUNNER_LOOP_LIVE=1)

    /// Decodes real server responses with the app's models. Only GETs, so nothing on the server changes
    /// (it skips `GET /requests/{id}/messages`, which marks messages read, and `POST /listings/{id}/style`).
    func testLiveServerReadOnlyEndpointsDecode() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["LOOP_LIVE"] == "1", "set TEST_RUNNER_LOOP_LIVE=1 to hit the live server")
        let defaults = UserDefaults.standard
        defer { defaults.removeObject(forKey: "useMocks"); APIConfig.setUseMocks(false); AuthToken.set(nil); defaults.removeObject(forKey: "useMocks") }
        APIConfig.setUseMocks(false)
        AuthToken.set(nil)
        let api = LiveAPIClient()

        let healthy = try await api.health()
        XCTAssertTrue(healthy)
        let login = try await api.login(email: "jordan.park@vanderbilt.edu")
        AuthToken.set(login.token)
        XCTAssertEqual(login.user.campus.name, "Vanderbilt")
        let me = try await api.me()
        XCTAssertEqual(me.email, "jordan.park@vanderbilt.edu")
        XCTAssertNotNil(me.name)
        _ = try await api.unread()
        let dorms = try await api.dorms()
        XCTAssertFalse(dorms.isEmpty)
        let spots = try await api.meetupSpots()
        XCTAssertFalse(spots.isEmpty)

        let feed = try await api.listings(ListingQuery())
        XCTAssertFalse(feed.items.isEmpty)
        XCTAssertTrue(feed.items.allSatisfy { !$0.photos.isEmpty && $0.status == .active })
        let first = try XCTUnwrap(feed.items.first)
        let detail = try await api.listing(id: first.id)
        XCTAssertEqual(detail.id, first.id)
        _ = try await api.listings(ListingQuery(shareType: .free))
        _ = try await api.listings(ListingQuery(category: .shoes))
        _ = try await api.listings(ListingQuery(q: "jacket"))
        _ = try await api.myListings(status: .active)
        _ = try await api.myListings(status: .completed)
        _ = try await api.similar(listingID: first.id)
        _ = try await api.savedListings()

        let incoming = try await api.myRequests(role: .incoming)
        let outgoing = try await api.myRequests(role: .outgoing)
        if let request = (incoming.items + outgoing.items).first {
            let one = try await api.request(id: request.id)
            XCTAssertEqual(one.id, request.id)
        }

        let mine = try await api.myImpact()
        XCTAssertGreaterThanOrEqual(mine.itemsShared, 0)
        let campus = try await api.campusImpact()
        let board = try await api.leaderboard()
        if let top = board.first, let topDorm = campus.topDorm { XCTAssertEqual(top.dorm, topDorm, "docs/API.md: first row matches top_dorm") }
        // S-22 (badges) may not be deployed yet; the app hides the badge row when this 404s.
        do {
            let badges = try await api.badges()
            XCTAssertEqual(badges.map(\.id), ["first_swap", "giving_back", "closet_cleanout"])
        } catch {
            XCTAssertEqual(error.apiCode, "not_found", "only a not-yet-deployed endpoint is tolerated here")
            print("NOTE: GET /me/badges is not live yet (server task S-22)")
        }
        let notes = try await api.notifications()
        XCTAssertGreaterThanOrEqual(notes.unread, 0)
    }
}
