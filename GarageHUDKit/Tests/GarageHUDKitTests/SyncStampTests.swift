import XCTest
@testable import GarageHUDKit

/// ADR-0005 tests 1 and 2 — the ordering primitive.
///
/// The whole design rests on this being trustworthy without trusting device clocks. If a fast phone
/// can win indefinitely, or if two devices merging the same pair disagree, everything built on top
/// inherits the flaw.
final class SyncStampTests: XCTestCase {

    private let mac = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let phone = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    private func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

    // MARK: Test 1 — skew

    func testAFastClockDoesNotWinForever() {
        // The phone is three minutes fast. Its edit outranks the Mac's, as any time-based scheme
        // would allow — that first round is unavoidable without a server clock.
        var phoneClock = SyncClock(node: phone)
        var macClock = SyncClock(node: mac)
        let phoneEdit = phoneClock.stamp(now: at(1_000 + 180))
        let macEdit = macClock.stamp(now: at(1_000))
        XCTAssertTrue(macEdit < phoneEdit)

        // But once the Mac observes it, the Mac adopts the higher reading. Its next edit orders
        // AFTER the phone's, despite its own clock still reading three minutes earlier. That is the
        // property that stops permanent silent victory.
        macClock.observe(phoneEdit, now: at(1_001))
        let macNext = macClock.stamp(now: at(1_002))
        XCTAssertTrue(phoneEdit < macNext, "the Mac must be able to win after seeing the fast stamp")
    }

    func testClockMovingBackwardsStillProducesForwardOrder() {
        // A manual clock change (or NTP correction) must not let an edit order before an earlier one.
        var clock = SyncClock(node: mac)
        let first = clock.stamp(now: at(5_000))
        let second = clock.stamp(now: at(4_000))   // wall clock jumped backwards
        XCTAssertTrue(first < second)
    }

    func testEditsInTheSameMillisecondStillOrder() {
        var clock = SyncClock(node: mac)
        let a = clock.stamp(now: at(10))
        let b = clock.stamp(now: at(10))
        XCTAssertTrue(a < b)
        XCTAssertEqual(b.counter, a.counter + 1)
    }

    // MARK: Test 2 — deterministic ties

    func testIdenticalTimeAndCounterResolveByNodeDeterministically() {
        let a = SyncStamp(millis: 1_000, counter: 3, node: mac)
        let b = SyncStamp(millis: 1_000, counter: 3, node: phone)
        // Same answer regardless of which side asks — otherwise two devices merging the same pair
        // would reach different results and diverge forever.
        XCTAssertEqual(a < b, !(b < a))
        XCTAssertTrue(a < b || b < a, "a tie must never be unresolvable")
    }

    func testOrderIsATotalOrderAcrossTheFields() {
        let base = SyncStamp(millis: 100, counter: 1, node: mac)
        XCTAssertTrue(base < SyncStamp(millis: 101, counter: 0, node: mac))   // time dominates
        XCTAssertTrue(base < SyncStamp(millis: 100, counter: 2, node: mac))   // then counter
        XCTAssertTrue(SyncStamp(millis: 100, counter: 1, node: mac)
                      < SyncStamp(millis: 100, counter: 1, node: phone))      // then node
    }

    // MARK: The legacy floor

    func testZeroIsOlderThanAnyRealStamp() {
        // An unstamped legacy value must lose to any deliberate edit from an upgraded client.
        var clock = SyncClock(node: mac)
        let real = clock.stamp(now: at(0))
        XCTAssertTrue(SyncStamp.zero < real)
        XCTAssertTrue(SyncStamp.zero.isZero)
    }

    func testStampSurvivesACodableRoundTrip() {
        let stamp = SyncStamp(millis: 1_726_000_000_123, counter: 7, node: phone)
        let data = try! JSONEncoder().encode(stamp)
        XCTAssertEqual(try! JSONDecoder().decode(SyncStamp.self, from: data), stamp)
    }

    func testObservingAnOlderStampDoesNotMoveTheClockBackwards() {
        var clock = SyncClock(node: mac)
        let ahead = clock.stamp(now: at(9_000))
        clock.observe(SyncStamp(millis: 1_000, counter: 0, node: phone), now: at(9_000))
        let next = clock.stamp(now: at(9_000))
        XCTAssertTrue(ahead < next)
    }
}
