import XCTest
@testable import GarageHUDKit

/// The conversational layer must stay evidence-first and honor driving-mode shaping —
/// these pin topic routing, the confidence-bearing answers, and the moving-vehicle brevity rule.
final class StewardConversationTests: XCTestCase {

    private func builtVehicle() -> Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, garageSlot: 1)
        v.factoryHorsepower = 200
        v.performanceRecords = [PerformanceRecord(type: .dyno, wheelHorsepower: 320)]
        v.documentedTotalInvestment = 19_000
        return v
    }

    func testTopicRouting() {
        XCTAssertEqual(StewardConversation.topic(for: "how much power do I have"), .power)
        XCTAssertEqual(StewardConversation.topic(for: "what have I spent so far"), .investment)
        XCTAssertEqual(StewardConversation.topic(for: "cost per horsepower?"), .efficiency)
        XCTAssertEqual(StewardConversation.topic(for: "anything I should watch"), .observations)
        XCTAssertEqual(StewardConversation.topic(for: "when did I last touch it"), .activity)
        XCTAssertEqual(StewardConversation.topic(for: "hey steward"), .greeting)
        XCTAssertEqual(StewardConversation.topic(for: ""), .unknown)
    }

    func testPowerAnswerPrefersMeasuredDynoWithBand() {
        let reply = StewardConversation.reply(to: "how much power", vehicle: builtVehicle())
        XCTAssertTrue(reply.text.contains("320"))
        XCTAssertEqual(reply.confidence, .strong)
    }

    func testPowerFallsBackToFactoryWhenNoDyno() {
        var v = builtVehicle()
        v.performanceRecords = []
        let reply = StewardConversation.reply(to: "how fast is it", vehicle: v)
        XCTAssertTrue(reply.text.localizedCaseInsensitiveContains("factory"))
        XCTAssertEqual(reply.confidence, .weak)
    }

    func testEfficiencyIsApproximateModerate() {
        let reply = StewardConversation.reply(to: "cost per hp", vehicle: builtVehicle())
        XCTAssertEqual(reply.confidence, .moderate)
    }

    func testMovingModeShortensToFirstSentence() {
        let parked = StewardConversation.reply(to: "how much power", vehicle: builtVehicle(), mode: .parked)
        let moving = StewardConversation.reply(to: "how much power", vehicle: builtVehicle(), mode: .moving)
        XCTAssertLessThanOrEqual(moving.text.count, parked.text.count)
    }

    func testResponderBoundaryReturnsSameText() async {
        let v = builtVehicle()
        let responder = StewardResponder(vehicle: v, mode: .parked)
        let text = await responder.respond(to: StewardIntent(raw: "cost per hp"))
        XCTAssertEqual(text, StewardConversation.reply(to: "cost per hp", vehicle: v).text)
    }

    func testActivityUsesInjectedClock() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var v = builtVehicle()
        v.performanceRecords = [PerformanceRecord(date: calendar.date(byAdding: .day, value: -12, to: now)!, type: .dyno)]

        let reply = StewardConversation.reply(
            to: "when did I last touch it",
            vehicle: v,
            context: StewardContext(now: now, calendar: calendar))

        XCTAssertTrue(reply.text.contains("12 days ago"))
    }
}
