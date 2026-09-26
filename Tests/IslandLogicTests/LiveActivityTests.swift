import XCTest
@testable import IslandLogic

final class LiveActivityPayloadTests: XCTestCase {
    private func push(_ json: String) -> Result<LiveActivityUpdate, LiveActivityError> {
        LiveActivityPayload.parsePush(Data(json.utf8))
    }

    func testValidFullPush() throws {
        let update = try push(##"{"id":"build","title":" Сборка ","subtitle":"swift build","symbol":"hammer.fill","progress":0.4,"color":"#ff9500","state":"running","dismiss":5}"##).get()
        XCTAssertEqual(update, LiveActivityUpdate(id: "build", title: "Сборка", subtitle: "swift build", symbol: "hammer.fill",
                                                  progress: 0.4, accentHex: "#FF9500", state: .running, dismissAfter: 5))
    }

    func testStateOnlyUpdateIsValid() throws {
        let update = try push(#"{"id":"build","state":"success"}"#).get()
        XCTAssertNil(update.title)
        XCTAssertEqual(update.state, .success)
    }

    func testRejectsBadFields() {
        XCTAssertEqual(push("not json"), .failure(.malformedJSON))
        XCTAssertEqual(push("[1]"), .failure(.malformedJSON))
        XCTAssertEqual(push(#"{"title":"x"}"#), .failure(.invalidField("id", "is required")))
        if case .failure(.invalidField("id", _)) = push(#"{"id":"../etc","title":"x"}"#) {} else { XCTFail("path-like id") }
        if case .failure(.invalidField("id", _)) = push(#"{"id":"\#(String(repeating: "a", count: 65))"}"#) {} else { XCTFail("long id") }
        XCTAssertEqual(push(#"{"id":"a","title":"   "}"#), .failure(.invalidField("title", "must not be empty")))
        if case .failure(.invalidField("title", _)) = push(#"{"id":"a","title":"\#(String(repeating: "x", count: 81))"}"#) {} else { XCTFail("long title") }
        if case .failure(.invalidField("progress", _)) = push(#"{"id":"a","progress":1.5}"#) {} else { XCTFail("progress > 1") }
        if case .failure(.invalidField("progress", _)) = push(#"{"id":"a","progress":-0.1}"#) {} else { XCTFail("progress < 0") }
        if case .failure(.invalidField("color", _)) = push(#"{"id":"a","color":"red"}"#) {} else { XCTFail("color") }
        if case .failure(.invalidField("state", _)) = push(#"{"id":"a","state":"done"}"#) {} else { XCTFail("state") }
        if case .failure(.invalidField("dismiss", _)) = push(#"{"id":"a","dismiss":99999}"#) {} else { XCTFail("dismiss") }
        if case .failure(.invalidField("symbol", _)) = push(#"{"id":"a","symbol":"Hammer Fill"}"#) {} else { XCTFail("symbol") }
    }

    func testClearBodies() {
        XCTAssertEqual(LiveActivityPayload.parseClear(Data()), .success(nil))
        XCTAssertEqual(LiveActivityPayload.parseClear(Data("{}".utf8)), .success(nil))
        XCTAssertEqual(LiveActivityPayload.parseClear(Data(#"{"id":"build"}"#.utf8)), .success("build"))
        XCTAssertEqual(LiveActivityPayload.parseClear(Data("x".utf8)), .failure(.malformedJSON))
    }
}

final class LiveActivityStoreTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testNewActivityNeedsTitleAndStartsRunningIndeterminate() throws {
        var store = LiveActivityStore()
        XCTAssertEqual(store.apply(LiveActivityUpdate(id: "a"), now: t0).map(\.id), .failure(.missingTitle))
        let a = try store.apply(LiveActivityUpdate(id: "a", title: "A"), now: t0).get()
        XCTAssertEqual(a.state, .running)
        XCTAssertNil(a.progress)
    }

    func testUpdateMergesOmittedFields() throws {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A", symbol: "hammer", progress: 0.2), now: t0)
        let a = try store.apply(LiveActivityUpdate(id: "a", progress: 0.6), now: t0 + 1).get()
        XCTAssertEqual(a.title, "A")
        XCTAssertEqual(a.symbol, "hammer")
        XCTAssertEqual(a.progress, 0.6)
    }

    func testActivityLimit() {
        var store = LiveActivityStore()
        for i in 0..<5 { store.apply(LiveActivityUpdate(id: "a\(i)", title: "x"), now: t0) }
        XCTAssertEqual(store.apply(LiveActivityUpdate(id: "extra", title: "x"), now: t0).map(\.id), .failure(.tooManyActivities(5)))
        // Updating an existing one still works when full.
        XCTAssertEqual(store.apply(LiveActivityUpdate(id: "a0", progress: 1), now: t0).map(\.id), .success("a0"))
    }

    func testFinishedActivityDismissesAfterItsDelay() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A"), now: t0)
        store.apply(LiveActivityUpdate(id: "a", state: .success, dismissAfter: 5), now: t0 + 10)
        XCTAssertEqual(store.nextExpiry(), t0 + 15)
        store.expire(now: t0 + 14.9)
        XCTAssertNotNil(store.current)
        store.expire(now: t0 + 15)
        XCTAssertNil(store.current)
    }

    func testFinishedWithoutDismissUsesDefault() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A", state: .failure), now: t0)
        XCTAssertEqual(store.nextExpiry(), t0 + store.rules.defaultDismissAfter)
    }

    func testRepeatingFinalStateDoesNotRestartDismissClock() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A", state: .success, dismissAfter: 5), now: t0)
        store.apply(LiveActivityUpdate(id: "a", state: .success), now: t0 + 3)
        XCTAssertEqual(store.nextExpiry(), t0 + 5)
    }

    func testRestartingClearsFinish() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A", state: .failure), now: t0)
        store.apply(LiveActivityUpdate(id: "a", state: .running), now: t0 + 1)
        XCTAssertNil(store.current?.finishedAt)
        XCTAssertEqual(store.nextExpiry(), t0 + 1 + store.rules.staleRunningAfter)
    }

    func testStaleRunningActivityExpires() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A"), now: t0)
        store.expire(now: t0 + store.rules.staleRunningAfter)
        XCTAssertTrue(store.activities.isEmpty)
    }

    func testSelectionPrefersLatestFinishThenLatestStart() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "old", title: "Old"), now: t0)
        store.apply(LiveActivityUpdate(id: "new", title: "New"), now: t0 + 1)
        XCTAssertEqual(store.current?.id, "new")
        // Progress on the older job doesn't steal the island.
        store.apply(LiveActivityUpdate(id: "old", progress: 0.9), now: t0 + 2)
        XCTAssertEqual(store.current?.id, "new")
        // Finishing does: the result is the news.
        store.apply(LiveActivityUpdate(id: "old", state: .success, dismissAfter: 5), now: t0 + 3)
        XCTAssertEqual(store.current?.id, "old")
        // Once dismissed, the running one comes back.
        store.expire(now: t0 + 8)
        XCTAssertEqual(store.current?.id, "new")
    }

    func testRemove() {
        var store = LiveActivityStore()
        store.apply(LiveActivityUpdate(id: "a", title: "A"), now: t0)
        XCTAssertEqual(store.remove(id: "missing").map { true }, .failure(.notFound("missing")))
        XCTAssertNotNil(try? store.remove(id: "a").get())
        XCTAssertNil(store.current)
    }
}

final class LiveActivityHTTPTests: XCTestCase {
    private let token = String(repeating: "ab", count: 32)

    private func raw(_ method: String = "POST", path: String = "/v1/activity", headers: [String] = [], body: String = "") -> Data {
        var head = "\(method) \(path) HTTP/1.1\r\n"
        for h in headers { head += h + "\r\n" }
        head += "Content-Length: \(body.utf8.count)\r\n\r\n"
        return Data((head + body).utf8)
    }

    private func authorize(_ headers: [String]) -> Result<Void, LiveActivityHTTPError> {
        let request = try! LiveActivityHTTP.parse(raw(headers: headers), maxBody: 4096).get()
        return LiveActivityHTTP.authorize(request, token: token, port: 47810)
    }

    func testParsesRequest() throws {
        let request = try LiveActivityHTTP.parse(raw(headers: ["Host: 127.0.0.1:47810"], body: "{}"), maxBody: 4096).get()
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/v1/activity")
        XCTAssertEqual(request.headers["host"], "127.0.0.1:47810")
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testIncompleteAndOversized() {
        XCTAssertEqual(LiveActivityHTTP.parse(Data("POST / HTTP/1.1\r\nHost: x".utf8), maxBody: 10).map { _ in true }, .failure(.incomplete))
        let partial = Data("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nab".utf8)
        XCTAssertEqual(LiveActivityHTTP.parse(partial, maxBody: 10).map { _ in true }, .failure(.incomplete))
        XCTAssertEqual(LiveActivityHTTP.parse(raw(body: String(repeating: "x", count: 11)), maxBody: 10).map { _ in true }, .failure(.tooLarge))
        XCTAssertEqual(LiveActivityHTTP.parse(Data(repeating: 65, count: 9000), maxBody: 10).map { _ in true }, .failure(.tooLarge))
    }

    func testRejectsSmugglingShapes() {
        let chunked = raw(headers: ["Transfer-Encoding: chunked"])
        XCTAssertEqual(LiveActivityHTTP.parse(chunked, maxBody: 10).map { _ in true }, .failure(.malformed))
        let twoHosts = raw(headers: ["Host: localhost", "Host: evil.com"])
        XCTAssertEqual(LiveActivityHTTP.parse(twoHosts, maxBody: 10).map { _ in true }, .failure(.malformed))
    }

    func testAuthorization() {
        let bearer = "Authorization: Bearer \(token)"
        XCTAssertNoThrow(try authorize(["Host: 127.0.0.1:47810", bearer]).get())
        XCTAssertNoThrow(try authorize(["Host: localhost", bearer]).get())
        XCTAssertEqual(authorize(["Host: 127.0.0.1:47810"]).map { true }, .failure(.unauthorized))
        XCTAssertEqual(authorize(["Host: 127.0.0.1:47810", "Authorization: Bearer wrong"]).map { true }, .failure(.unauthorized))
        XCTAssertEqual(authorize(["Host: 127.0.0.1:47810", "Authorization: Bearer \(token)x"]).map { true }, .failure(.unauthorized))
    }

    func testBrowserOriginIsRefusedEvenWithToken() {
        let result = authorize(["Host: 127.0.0.1:47810", "Origin: https://evil.example", "Authorization: Bearer \(token)"])
        XCTAssertEqual(result.map { true }, .failure(.forbiddenOrigin))
        XCTAssertEqual(authorize(["Host: localhost", "Origin: null", "Authorization: Bearer \(token)"]).map { true }, .failure(.forbiddenOrigin))
    }

    func testNonLoopbackHostIsRefused() {
        let bearer = "Authorization: Bearer \(token)"
        XCTAssertEqual(authorize(["Host: evil.example:47810", bearer]).map { true }, .failure(.badHost))
        XCTAssertEqual(authorize(["Host: 127.0.0.1.nip.io", bearer]).map { true }, .failure(.badHost))
        XCTAssertEqual(authorize([bearer]).map { true }, .failure(.badHost))
    }

    func testEmptyServerTokenNeverMatches() {
        let request = try! LiveActivityHTTP.parse(raw(headers: ["Host: localhost", "Authorization: Bearer "]), maxBody: 10).get()
        XCTAssertEqual(LiveActivityHTTP.authorize(request, token: "", port: 47810).map { true }, .failure(.unauthorized))
    }
}
