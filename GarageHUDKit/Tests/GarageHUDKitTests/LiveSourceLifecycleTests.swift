import XCTest
@testable import GarageHUDKit

/// The lifecycle contract: stop() halts production but keeps the stream open, so the same
/// source can be started again and subscribers keep receiving. (Reusable, not single-use.)
final class LiveSourceLifecycleTests: XCTestCase {

    func testStopThenStartKeepsStreamAlive() async {
        let source = SimulatedLiveDataSource()
        let received = Received()

        let consumer = Task {
            for await frame in source.frames {
                await received.add(frame)
                if await received.count >= 2 { break }
            }
        }

        source.start()
        try? await Task.sleep(nanoseconds: 300_000_000)
        source.stop()
        XCTAssertEqual(source.connectionState, .disconnected)

        // Restart the *same* source — a single-use source would strand the consumer here.
        source.start()
        try? await Task.sleep(nanoseconds: 300_000_000)

        let got = await received.count
        source.stop()
        consumer.cancel()
        XCTAssertGreaterThanOrEqual(got, 2, "same source should keep delivering after restart")
    }

    private actor Received {
        private(set) var count = 0
        func add(_ frame: LiveTelemetryFrame) { count += 1 }
    }
}
