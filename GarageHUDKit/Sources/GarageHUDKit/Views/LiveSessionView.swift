import SwiftUI

struct LiveSessionView: View {
    @Binding var vehicle: Vehicle

    @State private var source: SimulatedLiveDataSource?
    @State private var isRunning = false
    @State private var latest: LiveMetrics?
    @State private var captured: [LiveMetrics] = []
    @State private var streamTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            statusIndicator

            HUDPanel(title: "Live Telemetry") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130))], spacing: 20) {
                    CircularGauge(value: latest?.rpm ?? 0, maxValue: 7500, label: "RPM", color: HUDTheme.cyan)
                    CircularGauge(value: latest?.speedMph ?? 0, maxValue: 160, label: "Speed", unit: "MPH", color: HUDTheme.cyan)
                    CircularGauge(value: latest?.boostPsi ?? 0, maxValue: 25, label: "Boost", unit: "PSI", color: HUDTheme.amber)
                    CircularGauge(value: latest?.throttlePercent ?? 0, maxValue: 100, label: "Throttle", unit: "%", color: HUDTheme.cyan)
                    CircularGauge(value: latest?.coolantTempF ?? 0, maxValue: 260, label: "Coolant", unit: "°F", color: HUDTheme.amber)
                }
                .frame(maxWidth: .infinity)
            }

            // Steward reasons over the (currently estimated) live frame in real time.
            if let latest, isRunning {
                let live = Steward.observe(live: latest, for: vehicle)
                if !live.isEmpty {
                    HUDPanel(title: "Steward — Live") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(live) { StewardObservationRow($0) }
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button(isRunning ? "Stop Session" : "Start Session") {
                    isRunning ? stop() : start()
                }
                .buttonStyle(HUDButtonStyle(color: isRunning ? HUDTheme.danger : HUDTheme.cyan))

                if !captured.isEmpty && !isRunning {
                    Button("Save as Performance Record") { saveRecord() }
                        .buttonStyle(HUDButtonStyle(color: HUDTheme.amber))
                }
            }

            Text("Simulated OBD-II feed for now — swap in a Bluetooth ELM327 adapter later without changing this screen.")
                .font(HUDTheme.monoFont(10))
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()
        }
        .padding(24)
        .background(HUDTheme.background)
        .onDisappear { stop() }
    }

    private var statusIndicator: some View {
        HStack(spacing: 8) {
            if isRunning {
                Circle().fill(HUDTheme.amber).frame(width: 8, height: 8).hudGlow(HUDTheme.amber, radius: 3)
                Text("LIVE SESSION ACTIVE").foregroundStyle(HUDTheme.amber)
            } else {
                Circle().fill(HUDTheme.textSecondary).frame(width: 8, height: 8)
                Text("SESSION IDLE").foregroundStyle(HUDTheme.textSecondary)
            }
        }
        .font(HUDTheme.monoFont(11, weight: .semibold))
        .tracking(1.5)
    }

    private func start() {
        captured = []
        let newSource = SimulatedLiveDataSource()
        source = newSource
        newSource.start()
        isRunning = true
        streamTask = Task {
            for await metrics in newSource.metricsStream {
                latest = metrics
                captured.append(metrics)
            }
        }
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
            notes: "Captured live session (\(captured.count) samples)",
            isFromLiveSession: true,
            capturedPoints: captured
        )
        vehicle.performanceRecords.append(record)
        captured = []
    }
}
