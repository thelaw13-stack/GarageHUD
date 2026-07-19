import XCTest
@testable import GarageHUDKit

/// The LLM Steward answers only from the grounding record, so that record must faithfully carry the
/// car's facts — power, spend, maintenance, and the reasoning engine's own observations with their
/// confidence bands. If a fact isn't in the record, the model can't (honestly) speak to it.
final class StewardGroundingTests: XCTestCase {
    private func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    private func boostedCar() -> Vehicle {
        var v = Vehicle(make: "Subaru", model: "Forester XT", year: 2008, nickname: "Fozzy", garageSlot: 1,
                        factoryHorsepower: 224)
        v.drivetrain = .awd
        v.documentedTotalInvestment = 14_857
        v.confirmedStockSystems = [.brakes]
        v.parts = [
            Part(name: "COBB 20G", category: .forcedInduction, status: .installed, installDate: daysAgo(200), cost: 1200),
            Part(name: "Fuel pump", category: .fueling, status: .installed, installDate: daysAgo(180), cost: 300),
            Part(name: "Big brakes", category: .brakes, status: .wishlist, cost: 2500),
        ]
        v.performanceRecords = [PerformanceRecord(date: daysAgo(60), type: .dyno, wheelHorsepower: 381)]
        v.buildEvents = [BuildEvent(date: daysAgo(30), title: "E85 tune", mileage: 92_000)]
        v.maintenance = [MaintenanceItem(name: "Oil", intervalMonths: 6, lastServiced: daysAgo(400))]  // overdue
        return v
    }

    func testRecordCarriesTheHeadlineFacts() {
        let r = StewardGrounding.record(for: boostedCar())
        XCTAssertTrue(r.contains("Fozzy"))
        XCTAssertTrue(r.contains("381 whp"), r)            // measured power
        XCTAssertTrue(r.contains("Strong evidence"))       // with its band
        XCTAssertTrue(r.contains("$14,857"))               // build-sheet total surfaced even though not all parts priced
        XCTAssertTrue(r.contains("AWD"))
        XCTAssertTrue(r.localizedCaseInsensitiveContains("wishlist") || r.contains("Planned"))
    }

    func testRecordFoldsInStewardObservationsWithConfidence() {
        // The overdue oil is a Steward observation; the record must surface it (with a band) so the
        // LLM inherits the reasoning rather than re-deriving it.
        let r = StewardGrounding.record(for: boostedCar())
        XCTAssertTrue(r.contains("Steward observations"))
        XCTAssertTrue(r.localizedCaseInsensitiveContains("overdue"))
        XCTAssertTrue(r.contains("Confirmed") || r.contains("Strong Evidence") || r.contains("Moderate Evidence"))
    }

    func testRecordMarksAnEstimateAsWeakWhenNoDyno() {
        var v = Vehicle(make: "VW", model: "Baja", year: 1970, garageSlot: 1, factoryHorsepower: 60)
        v.buildEvents = [BuildEvent(title: "Acquired")]
        let r = StewardGrounding.record(for: v)
        XCTAssertTrue(r.contains("60 hp factory rating"))
        XCTAssertTrue(r.contains("Weak"))                  // never presented as measured
        XCTAssertFalse(r.contains("whp on the dyno"))
    }

    func testInstructionsForbidInvention() {
        let i = StewardGrounding.instructions
        XCTAssertTrue(i.localizedCaseInsensitiveContains("only from"))
        XCTAssertTrue(i.localizedCaseInsensitiveContains("never invent"))
        XCTAssertTrue(i.localizedCaseInsensitiveContains("confidence"))
    }

    func testPromptEmbedsBothRecordAndQuestion() {
        let p = StewardGrounding.prompt(question: "Will my fueling keep up if I raise boost?", vehicle: boostedCar())
        XCTAssertTrue(p.contains("VEHICLE RECORD"))
        XCTAssertTrue(p.contains("Will my fueling keep up"))
    }

    func testKeywordCoreAlwaysAnswersFromRecord() {
        // The deterministic fallback the assistant guarantees when no LLM is present — tested
        // directly so it stays fast and stable regardless of the host's Apple Intelligence status.
        let reply = StewardConversation.reply(to: "how much power?", vehicle: boostedCar())
        XCTAssertFalse(reply.text.isEmpty)
        XCTAssertTrue(reply.text.contains("381"))
        XCTAssertEqual(reply.confidence, .strong)
    }

    func testAssistantNeverReturnsEmpty() async {
        // Contract: the owner always gets *something* grounded, whether the answer came from the
        // on-device LLM or the keyword core. (No exact-content assertion — LLM phrasing varies.)
        let reply = await StewardAssistant.answer(question: "how much power?", vehicle: boostedCar())
        XCTAssertFalse(reply.text.isEmpty)
    }

    // MARK: W-061 — derived figures must never read as additive
    //
    // Field-found 2026-07-19 on Tim's phone: asked how much power the car makes, the on-device LLM
    // took the 381 whp measured figure, added the ~201 whp "gained over stock" estimate, and
    // reported the sum as fact. The gain is DERIVED from the measurement (measured − stock
    // baseline), so it was already inside the 381. These pin the record's wording so the two can
    // never again be presented as independent addable quantities.

    func testGainOverStockIsMarkedAsContainedInTheMeasuredFigure() {
        let car = boostedCar()
        let r = StewardGrounding.record(for: car)
        guard let gained = car.horsepowerGainedOverStock else {
            return XCTFail("fixture must produce a gain figure for this regression to mean anything")
        }
        XCTAssertTrue(r.contains("\(Int(gained)) whp of that 381 whp"), r)
        XCTAssertTrue(r.localizedCaseInsensitiveContains("already included"), r)
        XCTAssertTrue(r.localizedCaseInsensitiveContains("not additional"), r)
        XCTAssertTrue(r.localizedCaseInsensitiveContains("do not add these together"), r)
    }

    func testMeasuredPowerIsLabelledAsTheTotalNotAComponent() {
        let r = StewardGrounding.record(for: boostedCar())
        XCTAssertTrue(r.contains("381 whp"), r)
        XCTAssertTrue(r.localizedCaseInsensitiveContains("current total power at the wheels"), r)
    }

    func testGainFactNeverStandsAloneAsABareNumber() {
        // The exact shape that caused the bug: "Gained over stock: ~201 whp [estimate]" with no
        // stated relationship to the measurement it came from.
        let car = boostedCar()
        let r = StewardGrounding.record(for: car)
        guard let gained = car.horsepowerGainedOverStock else { return XCTFail("no gain in fixture") }
        XCTAssertFalse(r.contains("Gained over stock: ~\(Int(gained)) whp [estimate]"), r)
    }

    func testInstructionsForbidCombiningRecordedValues() {
        let i = StewardGrounding.instructions
        XCTAssertTrue(i.localizedCaseInsensitiveContains("do not add"), i)
        XCTAssertTrue(i.localizedCaseInsensitiveContains("derived"), i)
        XCTAssertTrue(i.localizedCaseInsensitiveContains("double-count"), i)
    }

    func testMoneyViewsAreMarkedNonAdditiveToo() {
        // Same structural trap as power: documentedReconcile and pricedSoFar are other views of the
        // same spend, not extra money on top of the total. This one is about Tim's actual dollars.
        var v = boostedCar()
        v.documentedTotalInvestment = 20_000       // documented total leads the priced parts sum
        let r = StewardGrounding.record(for: v)
        XCTAssertTrue(r.localizedCaseInsensitiveContains("whole build investment figure"), r)
        if let fig = v.investmentFigure, fig.pricedSoFar != nil || fig.documentedReconcile != nil {
            XCTAssertTrue(r.localizedCaseInsensitiveContains("not additional to"), r)
        }
    }
}
