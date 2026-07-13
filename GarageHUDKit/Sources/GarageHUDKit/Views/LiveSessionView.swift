import SwiftUI

struct LiveSessionView: View {
    @Binding var vehicle: Vehicle

    private enum Feed: String, CaseIterable, Identifiable { case simulated = "Simulated", adapter = "OBD-II Adapter"; var id: String { rawValue } }
    @State private var feed: Feed = .simulated

    @State private var source: LiveDataSource?
    @State private var isRunning = false
    @State private var frame: LiveTelemetryFrame?
    @State private var displayed: LiveMetrics?        // carried-over needle positions
    @State private var captured: [LiveMetrics] = []
    @State private var streamTask: Task<Void, Never>?

    // Pull Guardian — detects a genuine WOT pull in the stream and grades what it saw.
    @State private var detector: PullDetector?
    @State private var sessionPulls: [PullReport] = []

    var body: some View {
        ScrollView {
            content
        }
        .background(HUDTheme.background)
        .onDisappear { stop() }
    }

    private var content: some View {
        VStack(spacing: 24) {
            statusIndicator

            Picker("Feed", selection: $feed) {
                ForEach(Feed.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(isRunning)
            .frame(maxWidth: 320)

            HUDPanel(title: "Live Telemetry") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 20) {
                    gauge(\.rpm, displayed?.rpm ?? 0, max: 7500, "RPM", unit: "", HUDTheme.cyan)
                    gauge(\.speedMph, displayed?.speedMph ?? 0, max: 160, "Speed", unit: "MPH", HUDTheme.cyan)
                    gauge(\.boostPsi, displayed?.boostPsi ?? 0, max: 25, "Boost", unit: "PSI", HUDTheme.amber)
                    gauge(\.throttlePercent, displayed?.throttlePercent ?? 0, max: 100, "Throttle", unit: "%", HUDTheme.cyan)
                    gauge(\.coolantTempF, displayed?.coolantTempF ?? 0, max: 260, "Coolant", unit: "°F", HUDTheme.amber)
                }
                .frame(maxWidth: .infinity)
            }

            // Steward reasons only over the *fresh* values in the current frame.
            if let frame, isRunning {
                let live = Steward.observe(frame: frame, for: vehicle)
                if !live.isEmpty {
                    HUDPanel(title: "Steward — Live") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(live) { StewardObservationRow($0) }
                        }
                    }
                }
            }

            // Pull Guardian: pulls auto-captured this session, each graded by how much of its
            // boost claim was actually measured — not just detected, but honestly scored.
            if !sessionPulls.isEmpty {
                HUDPanel(title: "Pulls This Session") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(sessionPulls.reversed(), id: \.id) { pull in
                            pullRow(pull)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(isRunning ? "Stop Session" : "Start Session") {
                    isRunning ? stop() : start()
                }
                .buttonStyle(ActionButton(isRunning ? .destructive : .primary))

                if !captured.isEmpty && !isRunning {
                    Button("Save as Performance Record") { saveRecord() }
                        .buttonStyle(.attentionAction)
                }
            }

            Text(feed == .adapter
                 ? "Reading a Bluetooth LE ELM327 adapter (experimental). Only values decoded live are tagged MEASURED; anything that stops responding drops out rather than freezing."
                 : "Simulated feed — plausible wandering values, always tagged ESTIMATED.")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if feed == .adapter {
                Text("Recommended: OBDLink CX (Bluetooth LE). The OBDLink MX+ is MFi/Bluetooth Classic and won't appear in a Bluetooth LE scan.")
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    /// A gauge that dims when its own value isn't fresh, so a frozen needle can't be mistaken
    /// for a live one.
    private func gauge(_ metric: KeyPath<LiveTelemetryFrame, TimedMeasurement<Double>?>,
                       _ value: Double, max: Double, _ label: String, unit: String, _ color: Color) -> some View {
        let fresh = frame?.fresh(metric) != nil
        return CircularGauge(value: value, maxValue: max, label: label, unit: unit, color: color)
            .opacity(isRunning && !fresh ? 0.35 : 1)
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if isRunning {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusText).foregroundStyle(statusColor)
            } else {
                Circle().fill(HUDTheme.textSecondary).frame(width: 8, height: 8)
                Text("SESSION IDLE").foregroundStyle(HUDTheme.textSecondary)
            }
        }
        .font(HUDTheme.label(.semibold))
        .tracking(1.5)
    }

    private var statusText: String {
        switch frame?.connectionState ?? .polling {
        case .polling: return feed == .adapter ? "LINKED · MEASURING" : "LIVE SESSION ACTIVE"
        case .degraded, .reconnecting: return "SIGNAL DEGRADED"
        case .disconnected: return "DISCONNECTED"
        default: return "CONNECTING…"
        }
    }

    private var statusColor: Color {
        switch frame?.connectionState ?? .polling {
        case .polling: return HUDTheme.amber
        case .degraded, .reconnecting, .disconnected: return HUDTheme.danger
        default: return HUDTheme.textSecondary
        }
    }

    private func start() {
        captured = []
        displayed = nil
        frame = nil
        sessionPulls = []
        detector = PullDetector(feedLabel: feed.rawValue, envelope: vehicle.operatingEnvelope)
        let newSource: LiveDataSource = makeSource()
        source = newSource
        newSource.start()
        isRunning = true
        streamTask = Task {
            for await incoming in newSource.frames {
                frame = incoming
                let snapshot = incoming.displaySnapshot(carryingOver: displayed)
                displayed = snapshot
                // Only bank a sample when the frame actually carries fresh data.
                if incoming.hasAnyFresh() { captured.append(snapshot) }
                // Pull Guardian sees every frame regardless of freshness — it needs stale/dropped
                // throttle to know a run just ended, not only fresh samples.
                if let report = detector?.ingest(incoming) {
                    sessionPulls.append(report)
                    vehicle.recordPullReport(report)
                }
            }
        }
    }

    private func pullRow(_ pull: PullReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pull.headline)
                    .font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                Spacer(minLength: 0)
                Text(pull.confidence.label)
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(pull.boostBreachedCeiling ? HUDTheme.danger : HUDTheme.textSecondary)
            }
            Text(pull.verdictStatement)
                .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    private func makeSource() -> LiveDataSource {
        #if canImport(CoreBluetooth)
        if feed == .adapter { return OBDLiveDataSource() }
        #endif
        return SimulatedLiveDataSource()
    }

    private func stop() {
        source?.stop()
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
    }

    private func saveRecord() {
        let record = PerformanceRecord(
            type: .boostLog,
            notes: "Captured live session (\(captured.count) samples, \(feed.rawValue))",
            isFromLiveSession: true,
            capturedPoints: captured
        )
        vehicle.performanceRecords.append(record)
        captured = []
    }
}
