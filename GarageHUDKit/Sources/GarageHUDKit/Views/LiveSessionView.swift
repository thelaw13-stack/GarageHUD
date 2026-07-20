import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct LiveSessionView: View {
    @Binding var vehicle: Vehicle

    private enum Feed: String, CaseIterable, Identifiable { case simulated = "Simulated", adapter = "OBD-II Adapter"; var id: String { rawValue } }
    @State private var feed: Feed = .simulated

    @State private var source: LiveDataSource?
    @State private var savedAdapterProfile: OBDAdapterProfile? = OBDAdapterProfileStore.load()
    @State private var adapterSelection = OBDAdapterSelectionStore.load()
    // Scan-first pairing: adapters seen this scan, and the one the owner tapped to validate.
    @State private var discoveredAdapters: [OBDAdapterCandidate] = []
    @State private var selectedAdapterID: UUID?
    @State private var lastConnectionJournal = OBDConnectionJournalStore.load()
    @State private var isRunning = false
    @State private var frame: LiveTelemetryFrame?
    @State private var displayed: LiveMetrics?        // carried-over needle positions
    @State private var captured: [LiveMetrics] = []
    @State private var streamTask: Task<Void, Never>?

    // Pull Guardian — detects a genuine WOT pull in the stream and grades what it saw.
    @State private var detector: PullDetector?
    @State private var sessionPulls: [PullReport] = []

    private var compatibleSavedProfile: OBDAdapterProfile? {
        guard let profile = savedAdapterProfile else { return nil }
        return adapterSelection.acceptsSavedProfile(profile) ? profile : nil
    }

    var body: some View {
        ScrollView {
            content
        }
        .background(HUDTheme.background)
        .onDisappear { stop() }
        // W-063: the dials are only watchable if the phone stays awake. Driven by session state,
        // not view lifetime, and re-evaluated as the link moves so a dropped adapter releases it.
        .onChange(of: isRunning) { _, _ in applyScreenWake() }
        .onChange(of: frame?.connectionState) { _, _ in applyScreenWake() }
    }

    /// Apply the wake decision. iOS-only: there is no idle timer to hold on macOS, and the policy
    /// itself stays pure and testable in `ScreenWake`.
    private func applyScreenWake() {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.isIdleTimerDisabled =
            ScreenWake.shouldStayAwake(sessionRunning: isRunning, connection: frame?.connectionState)
        #endif
    }

    /// Always release the hold, whatever the session state believes. Called on stop so a session
    /// that ends by any path — button, error, or the view going away — cannot strand the screen on.
    private func releaseScreenWake() {
        #if canImport(UIKit) && !os(watchOS)
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
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

            if feed == .adapter && !vehicle.supportsOBD2 {
                preOBD2Notice
            } else if feed == .adapter {
                adapterConnectionPanel
                // Fresh pairing: surface discovered adapters to choose from. Hidden once a known
                // adapter is saved (that path reconnects straight to the validated device).
                if compatibleSavedProfile == nil && isRunning && !discoveredAdapters.isEmpty {
                    adapterCandidatePanel
                }
                if !isRunning, let journal = lastConnectionJournal {
                    connectionJournalPanel(journal)
                }
            }

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

            pullGuardianPanel

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

            HStack(spacing: 12) {
                Button(sessionButtonTitle) {
                    isRunning ? stop() : start()
                }
                .buttonStyle(ActionButton(isRunning ? .destructive : .primary))
                .disabled(!isRunning && feed == .adapter
                          && (!adapterSelection.canConnectDirectly || !vehicle.supportsOBD2))

                if !captured.isEmpty && !isRunning {
                    Button("Save as Performance Record") { saveRecord() }
                        .buttonStyle(.attentionAction)
                }
            }

            Text(feed == .adapter
                 ? adapterSelection.setupDetail
                 : "Simulated feed — plausible wandering values, always tagged ESTIMATED.")
                .font(HUDTheme.label())
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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
        case .scanning: return "SEARCHING"
        case .connecting: return "OPENING LINK"
        case .discoveringServices, .discoveringCharacteristics: return "PAIRING"
        case .resetting, .configuring, .ready: return "NEGOTIATING"
        }
    }

    private var statusColor: Color {
        switch frame?.connectionState ?? (feed == .simulated && isRunning ? .polling : .disconnected) {
        case .polling: return HUDTheme.amber
        case .degraded, .reconnecting, .disconnected: return HUDTheme.danger
        default: return HUDTheme.textSecondary
        }
    }

    private var preOBD2Notice: some View {
        HUDPanel(title: "Live Telemetry", caption: "unavailable") {
            HStack(alignment: .top, spacing: HUDTheme.space3) {
                Image(systemName: "bolt.slash")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 6).fill(HUDTheme.hairline))
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(vehicle.displayName) predates OBD-II")
                        .font(HUDTheme.body(.bold)).foregroundStyle(HUDTheme.textPrimary)
                    Text("OBD-II arrived on US cars in 1996, so there's no port to connect an adapter to. Live telemetry isn't available for this car — the Simulated feed still works.")
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var adapterConnectionPanel: some View {
        let detail = frame?.connectionDetail
        let state = frame?.connectionState ?? (isRunning ? .scanning : .disconnected)
        let profile = compatibleSavedProfile
        return HUDPanel(title: "Adapter Link", caption: profile == nil ? "Hardware setup" : "Known adapter") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                if !isRunning {
                    HStack(spacing: HUDTheme.space3) {
                        Label("Adapter", systemImage: "dot.radiowaves.left.and.right")
                            .font(HUDTheme.body(.semibold))
                            .foregroundStyle(HUDTheme.textPrimary)
                        Spacer(minLength: HUDTheme.space2)
                        Picker("Adapter model", selection: $adapterSelection) {
                            ForEach(OBDAdapterSelection.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(HUDTheme.cyan)
                        .onChange(of: adapterSelection) { _, selection in
                            OBDAdapterSelectionStore.save(selection)
                        }
                    }
                    Divider().overlay(HUDTheme.hairline)
                }

                HStack(spacing: HUDTheme.space3) {
                    Image(systemName: adapterIcon(for: state))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(statusColor.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail?.adapterName ?? profile?.name ?? adapterSelection.displayName)
                            .font(HUDTheme.body(.bold))
                            .foregroundStyle(HUDTheme.textPrimary)
                        Text(detail?.message ?? (isRunning ? "Preparing Bluetooth…" : "Ready to connect"))
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: HUDTheme.space2)
                    if detail?.attempt ?? 0 > 0 {
                        Text("TRY \(detail?.attempt ?? 0)")
                            .font(HUDTheme.label(.semibold))
                            .foregroundStyle(HUDTheme.amber)
                            .tracking(1)
                    }
                }

                connectionRail(state)

                if !adapterSelection.canConnectDirectly && !isRunning {
                    HStack(alignment: .top, spacing: HUDTheme.space2) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(HUDTheme.amber)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("MX+ DATA ACCESS PENDING")
                                .font(HUDTheme.label(.semibold))
                                .foregroundStyle(HUDTheme.amber)
                                .tracking(1)
                            Text("Seeing MX+ in iPhone Bluetooth confirms pairing, not app data access. GarageHUD needs OBDLink's protected iOS accessory protocol before it can open that channel.")
                                .font(HUDTheme.label())
                                .foregroundStyle(HUDTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let recovery = detail?.recovery, isRunning {
                    HStack(alignment: .top, spacing: HUDTheme.space2) {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundStyle(HUDTheme.amber)
                        Text(recovery)
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if profile != nil && !isRunning {
                    Button {
                        OBDAdapterProfileStore.forget()
                        savedAdapterProfile = nil
                    } label: {
                        Label("Forget Saved Adapter", systemImage: "trash")
                    }
                    .buttonStyle(.compactAction)
                }
            }
        }
    }

    private var adapterCandidatePanel: some View {
        HUDPanel(title: "Discovered Adapters", caption: "tap to validate") {
            VStack(spacing: 10) {
                Text("GarageHUD remembers an adapter only after its ELM327 identity check succeeds.")
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(discoveredAdapters) { candidate in
                    candidateRow(candidate)
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private func candidateRow(_ candidate: OBDAdapterCandidate) -> some View {
        AdapterCandidateRow(candidate: candidate,
                            selected: selectedAdapterID == candidate.peripheralID,
                            enabled: isRunning) { connect(to: candidate) }
    }

    private func connectionRail(_ state: OBDConnectionState) -> some View {
        let active = connectionProgress(state)
        return HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { index in
                Capsule()
                    .fill(index <= active ? statusColor : HUDTheme.hairline)
                    .frame(height: 5)
            }
        }
        .accessibilityLabel("Connection progress")
        .accessibilityValue("\(max(0, active + 1)) of 4")
    }

    private func connectionProgress(_ state: OBDConnectionState) -> Int {
        switch state {
        case .disconnected, .scanning: return 0
        case .connecting: return 1
        case .discoveringServices, .discoveringCharacteristics, .resetting, .configuring, .ready: return 2
        case .polling: return 3
        case .degraded, .reconnecting: return 1
        }
    }

    private func adapterIcon(for state: OBDConnectionState) -> String {
        switch state {
        case .polling: return "checkmark.circle.fill"
        case .degraded, .reconnecting, .disconnected: return "exclamationmark.triangle.fill"
        case .scanning: return "dot.radiowaves.left.and.right"
        default: return "link"
        }
    }

    private var pullGuardianPanel: some View {
        HUDPanel(title: "Pull Guardian", caption: guardianCaption) {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                HStack(alignment: .firstTextBaseline, spacing: HUDTheme.space2) {
                    Circle().fill(guardianColor).frame(width: 8, height: 8)
                    Text(guardianState)
                        .font(HUDTheme.body(.semibold))
                        .foregroundStyle(guardianColor)
                    Spacer(minLength: HUDTheme.space2)
                    if let detector, detector.isCapturing {
                        Text("\(detector.activeSampleCount) SAMPLES")
                            .font(HUDTheme.label(.semibold))
                            .foregroundStyle(HUDTheme.textSecondary)
                            .tracking(1)
                    }
                }

                Text(guardianDetail)
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                rpmRunway

                if !sessionPulls.isEmpty {
                    Divider().overlay(HUDTheme.hairline)
                    ForEach(sessionPulls.reversed(), id: \.id) { pull in
                        pullRow(pull)
                    }
                    let intelligence = PullIntelligence.analyze(vehicle.pullReports)
                    HStack(alignment: .top, spacing: HUDTheme.space2) {
                        Image(systemName: intelligence.state == .hold ? "hand.raised.fill" : "waveform.path.ecg")
                            .foregroundStyle(intelligence.state == .hold ? HUDTheme.danger : HUDTheme.cyan)
                        Text(intelligence.nextAction)
                            .font(HUDTheme.label(.medium))
                            .foregroundStyle(HUDTheme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, HUDTheme.space1)
                }
            }
        }
    }

    private var guardianState: String {
        guard isRunning else { return "STANDING BY" }
        return detector?.isCapturing == true ? "CAPTURING PULL" : "WATCHING FOR LOAD"
    }

    private var guardianCaption: String {
        guard isRunning else { return "Arm at 65% throttle" }
        return detector?.isCapturing == true ? "Lift closes the report" : "Structured memory armed"
    }

    private var guardianDetail: String {
        if let detector, detector.isCapturing, let start = detector.activeRPMStart {
            return "Pull opened at \(Int(start)) rpm. Guardian is collecting band fit, ceiling, coolant, source, and evidence confidence."
        }
        if let pull = sessionPulls.last {
            return "Last capture: \(pull.headline). \(pull.confidence.label) evidence was saved to this vehicle."
        }
        return "A sustained run is banked automatically after at least 2 seconds and 400 rpm of rise."
    }

    private var guardianColor: Color {
        guard isRunning else { return HUDTheme.textSecondary }
        return detector?.isCapturing == true ? HUDTheme.amber : HUDTheme.green
    }

    private var rpmRunway: some View {
        let bands = vehicle.operatingEnvelope.expectedBoostByRPM.sorted { $0.rpmLow < $1.rpmLow }
        let minimum = Double(min(bands.first?.rpmLow ?? 1000, 1000))
        let maximum = Double(max(bands.last?.rpmHigh ?? 7500, 7500))
        let rpm = displayed?.rpm ?? minimum
        let position = ((rpm - minimum) / max(1, maximum - minimum)).clamped(to: 0...1)

        return VStack(alignment: .leading, spacing: HUDTheme.space1) {
            HStack {
                Text("RPM RUNWAY")
                Spacer()
                Text("\(Int(rpm)) RPM")
            }
            .font(HUDTheme.label(.semibold))
            .foregroundStyle(HUDTheme.textTertiary)
            .tracking(1)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(HUDTheme.hairline).frame(height: 8)
                    ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                        let start = (Double(band.rpmLow) - minimum) / max(1, maximum - minimum)
                        let width = Double(band.rpmHigh - band.rpmLow) / max(1, maximum - minimum)
                        Capsule()
                            .fill((index.isMultiple(of: 2) ? HUDTheme.cyan : HUDTheme.green).opacity(0.55))
                            .frame(width: max(3, proxy.size.width * width), height: 8)
                            .offset(x: proxy.size.width * start)
                    }
                    Rectangle()
                        .fill(guardianColor)
                        .frame(width: 3, height: 22)
                        .offset(x: max(0, min(proxy.size.width - 3, proxy.size.width * position)))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
        }
    }

    private func start() {
        captured = []
        displayed = nil
        frame = nil
        sessionPulls = []
        discoveredAdapters = []
        selectedAdapterID = nil
        detector = PullDetector(feedLabel: feed.rawValue, envelope: vehicle.operatingEnvelope)
        run(makeSource())
    }

    /// Own a source and consume its frame stream. Shared by `start()` and by `connect(to:)` when the
    /// owner taps a discovered adapter, so re-targeting a scan reuses the exact same live loop.
    private func run(_ newSource: LiveDataSource) {
        source = newSource
        newSource.start()
        isRunning = true
        streamTask = Task {
            for await incoming in newSource.frames {
                frame = incoming
                if let obd = newSource as? OBDLiveDataSource,
                   let profile = obd.discoveredProfile,
                   profile != savedAdapterProfile {
                    savedAdapterProfile = profile
                }
                if feed == .adapter {
                    lastConnectionJournal = OBDConnectionJournalStore.load()
                }
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

    /// Re-target the live scan at the adapter the owner tapped: connect to that exact peripheral and
    /// validate it. Recording its implied model first is what lets the saved profile be accepted on
    /// the next launch (reconnection is gated by `adapterSelection.acceptsSavedProfile`).
    private func connect(to candidate: OBDAdapterCandidate) {
        #if canImport(CoreBluetooth)
        guard isRunning, candidate.isReachableOverBLE else { return }
        selectedAdapterID = candidate.peripheralID
        adapterSelection = candidate.impliedSelection
        OBDAdapterSelectionStore.save(candidate.impliedSelection)
        source?.stop()
        streamTask?.cancel()
        streamTask = nil
        frame = nil
        run(makeAdapterSource(knownPeripheralID: candidate.peripheralID, autoConnect: true))
        #endif
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
        if feed == .adapter {
            if let profile = compatibleSavedProfile {
                // Known adapter: reconnect straight to the validated device.
                return makeAdapterSource(knownProfile: profile, autoConnect: true)
            }
            // Fresh pairing: scan-first — surface candidates and wait for the owner's tap.
            return makeAdapterSource(autoConnect: false)
        }
        #endif
        return SimulatedLiveDataSource()
    }

    #if canImport(CoreBluetooth)
    /// Build an OBD source wired to the pairing UI: it feeds discovered candidates to the picker and
    /// reports a validated profile so only a device that actually handshook is remembered.
    private func makeAdapterSource(knownPeripheralID: UUID? = nil,
                                   knownProfile: OBDAdapterProfile? = nil,
                                   autoConnect: Bool) -> OBDLiveDataSource {
        let adapter = OBDLiveDataSource(knownPeripheralID: knownPeripheralID,
                                        knownProfile: knownProfile,
                                        adapterSelection: adapterSelection,
                                        autoConnectDiscoveredPeripheral: autoConnect)
        adapter.onCandidateDiscovered = { candidate in
            discoveredAdapters = OBDAdapterCandidateList.upserting(candidate, into: discoveredAdapters)
        }
        adapter.onProfileValidated = { profile in
            savedAdapterProfile = profile   // now compatibleSavedProfile is non-nil → picker hides
        }
        return adapter
    }
    #endif

    private func stop() {
        source?.stop()
        if feed == .adapter {
            lastConnectionJournal = OBDConnectionJournalStore.load()
        }
        streamTask?.cancel()
        streamTask = nil
        isRunning = false
        releaseScreenWake()
    }

    private var sessionButtonTitle: String {
        if isRunning { return "Stop Session" }
        if feed == .adapter && !adapterSelection.canConnectDirectly { return "MX+ Access Required" }
        return "Start Session"
    }

    private func connectionJournalPanel(_ journal: OBDConnectionJournal) -> some View {
        let entries = Array(journal.entries.suffix(7))
        let diagnosis = journal.diagnosis
        let color = diagnosis.isSuccessful ? HUDTheme.green : HUDTheme.amber
        return HUDPanel(title: "Last Connection Report", caption: journal.adapterSelection.displayName) {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                HStack(alignment: .top, spacing: HUDTheme.space3) {
                    Image(systemName: diagnosis.isSuccessful ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: 6).fill(color.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosis.title.uppercased())
                            .font(HUDTheme.label(.bold))
                            .foregroundStyle(color)
                            .tracking(1)
                        Text(diagnosis.detail)
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(HUDTheme.hairline)

                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: HUDTheme.space3) {
                        Text(entry.stage)
                            .font(HUDTheme.label(.bold))
                            .foregroundStyle(entry.stage == "MEASURING" ? HUDTheme.green : HUDTheme.cyan)
                            .tracking(1)
                            .frame(width: 82, alignment: .leading)
                        Text(entry.message)
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Divider().overlay(HUDTheme.hairline)

                HStack(alignment: .top, spacing: HUDTheme.space2) {
                    Image(systemName: diagnosis.isSuccessful ? "checkmark.circle" : "arrow.turn.down.right")
                        .foregroundStyle(color)
                    Text(diagnosis.nextAction)
                        .font(HUDTheme.label(.medium))
                        .foregroundStyle(HUDTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ShareLink(item: SharableTextFile(fileName: "GarageHUD OBD-II connection report",
                                                 text: journal.supportReport),
                          preview: SharePreview("GarageHUD OBD-II connection report")) {
                    Label("Share Connection Report", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.compactAction)
            }
        }
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

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
