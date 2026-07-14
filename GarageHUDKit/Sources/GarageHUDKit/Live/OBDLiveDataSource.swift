import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

/// A real OBD-II feed over a Bluetooth-LE ELM327 adapter. Conforms to `LiveDataSource`, so it
/// drops into the Live HUD unchanged — but it is honest about its data in ways the transport
/// type alone can never guarantee:
///
///  • **Per-metric provenance/freshness.** Each PID reply becomes a `TimedMeasurement` tagged
///    `.obdAdapter` at the instant it arrives. A PID that stops answering simply stops being
///    fresh; its value goes *unavailable* downstream rather than freezing at the last reading.
///    A frame is never "measured" as a whole — only the individual values that truly are.
///
///  • **A real serial state machine.** ELM327 clones are command-response devices: this runs
///    exactly one command at a time, sends the next only after a prompt-terminated reply or a
///    controlled timeout, and drives bring-up through the tested `ELM327Handshake`. Failures
///    degrade and reconnect instead of silently polling a dead link.
///
///  • **Reusable lifecycle.** `stop()` halts transport and polling but leaves the stream open;
///    `deinit` finishes it. The same source can be started again.
///
/// EXPERIMENTAL: the decoding math and handshake logic are unit-tested, but this BLE transport
/// has not yet been exercised against physical hardware.
/// Thread-confinement invariant: every method and all mutable state are confined to the main
/// run loop. `start()`/`stop()` are called from the UI (main); the `CBCentralManager` is created
/// with the main queue so all delegate callbacks arrive on main; the timeout/reconnect timers
/// dispatch to `DispatchQueue.main`. Because that confinement is real but invisible to the
/// compiler, this is `@unchecked Sendable` rather than actor-isolated (a CoreBluetooth delegate
/// can't be `@MainActor` — its callbacks are nonisolated protocol requirements).
public final class OBDLiveDataSource: NSObject, LiveDataSource, @unchecked Sendable {

    public let frames: AsyncStream<LiveTelemetryFrame>
    private let continuation: AsyncStream<LiveTelemetryFrame>.Continuation
    public private(set) var connectionState: OBDConnectionState = .disconnected {
        didSet { if oldValue != connectionState { emitFrame() } }
    }
    public private(set) var connectionDetail = OBDConnectionDetail(message: "Adapter idle")

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private var pairedServiceUUID: String?
    private let serviceUUIDs: [CBUUID] = [CBUUID(string: "FFF0"), CBUUID(string: "FFE0")]
    private var adapterName: String?
    private var scanToken = 0
    private var linkToken = 0

    /// When set, only this peripheral will be connected — reconnection to a *validated* device
    /// rather than the first serial adapter that advertises. Pass a profile's `peripheralID`.
    public var knownPeripheralID: UUID?
    /// The validated profile assembled once bring-up succeeds. The app persists this so future
    /// sessions can set `knownPeripheralID` and skip blind discovery.
    public private(set) var discoveredProfile: OBDAdapterProfile?

    public init(knownPeripheralID: UUID? = nil, knownProfile: OBDAdapterProfile? = nil) {
        self.knownPeripheralID = knownProfile?.peripheralID ?? knownPeripheralID
        self.adapterName = knownProfile?.name
        var captured: AsyncStream<LiveTelemetryFrame>.Continuation!
        self.frames = AsyncStream { captured = $0 }
        self.continuation = captured
        super.init()
    }

    private var handshake = ELM327Handshake()
    private let pids = OBDPID.allCases
    private var pidCursor = 0
    private var consecutivePollTimeouts = 0
    private let maxPollTimeouts = OBDPID.allCases.count + 2
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5

    // In-flight command tracking — exactly one at a time, prompt-gated.
    private var buffer = ""
    private var inFlightCommand: String?
    private var timeoutToken = 0
    private var stopped = true

    // Per-metric measurements, each stamped when its reply actually arrives.
    private var rpm, speedMph, coolant, boost, throttle: TimedMeasurement<Double>?

    deinit { continuation.finish() }

    // MARK: Lifecycle

    public func start() {
        stopped = false
        reconnectAttempts = 0
        resetMeasurements()
        transition(.scanning, "Opening Bluetooth…", recovery: "Keep the adapter powered and the vehicle ignition on.")
        central = CBCentralManager(delegate: self, queue: .main) // confine callbacks to main
    }

    public func stop() {
        stopped = true
        invalidateTimeout()
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        central?.stopScan()
        scanToken += 1
        linkToken += 1
        transition(.disconnected, "Session stopped")
        // Stream stays open (reusable); deinit finishes it.
    }

    private func resetMeasurements() {
        rpm = nil; speedMph = nil; coolant = nil; boost = nil; throttle = nil
        pidCursor = 0; consecutivePollTimeouts = 0; handshake = ELM327Handshake()
    }

    private func transition(_ state: OBDConnectionState, _ message: String,
                            recovery: String? = nil, attempt: Int? = nil) {
        connectionDetail = OBDConnectionDetail(
            adapterName: adapterName,
            message: message,
            recovery: recovery,
            attempt: attempt ?? reconnectAttempts)
        if connectionState == state { emitFrame() } else { connectionState = state }
    }

    private func beginScan(_ central: CBCentralManager, message: String = "Searching for an OBD-II adapter…") {
        scanToken += 1
        let token = scanToken
        transition(.scanning, message,
                   recovery: "For an OBDLink CX, start the engine and keep other OBD apps closed.")
        central.scanForPeripherals(withServices: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.stopped, token == self.scanToken,
                  self.connectionState == .scanning else { return }
            if self.knownPeripheralID != nil {
                self.knownPeripheralID = nil
                guard let central = self.central else { return }
                self.beginScan(central, message: "Saved adapter was not reachable. Searching for a fresh OBDLink…")
            } else {
                self.transition(.scanning, "No compatible Bluetooth LE adapter seen yet",
                                recovery: "Confirm the model is OBDLink CX, power-cycle it, and close the OBDLink app.")
            }
        }
    }

    private func connect(_ peripheral: CBPeripheral, using central: CBCentralManager, name: String?) {
        scanToken += 1
        central.stopScan()
        self.peripheral = peripheral
        adapterName = KnownOBDAdapter.match(advertisedName: name)?.displayName ?? name ?? adapterName ?? "OBD-II Adapter"
        peripheral.delegate = self
        transition(.connecting, "Found \(adapterName ?? "adapter"). Opening secure link…",
                   recovery: "Leave the adapter powered and approve any iPhone pairing prompt.")
        central.connect(peripheral)

        linkToken += 1
        let token = linkToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            guard let self, !self.stopped, token == self.linkToken,
                  self.connectionState == .connecting else { return }
            guard let central = self.central, let peripheral = self.peripheral else { return }
            central.cancelPeripheralConnection(peripheral)
            self.knownPeripheralID = nil
            self.beginScan(central, message: "That adapter did not open. Searching again…")
        }
    }

    // MARK: Serial engine (one command in flight, prompt-gated)

    private func transmit(_ command: String, timeout: TimeInterval) {
        guard let peripheral, let writeChar,
              let data = (command + "\r").data(using: .ascii) else { return }
        inFlightCommand = command
        let type: CBCharacteristicWriteType =
            writeChar.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(data, for: writeChar, type: type)
        armTimeout(timeout)
    }

    private func armTimeout(_ seconds: TimeInterval) {
        timeoutToken += 1
        let token = timeoutToken
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.stopped, token == self.timeoutToken, self.inFlightCommand != nil else { return }
            self.onTimeout()
        }
    }

    private func invalidateTimeout() { timeoutToken += 1; inFlightCommand = nil }

    /// Bytes arrive in chunks; a reply is complete at the ELM327 ">" prompt. Decode each
    /// completed line against the command that's currently in flight.
    private func ingest(_ text: String) {
        buffer += text
        while let prompt = buffer.range(of: ">") {
            let line = String(buffer[..<prompt.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(..<prompt.upperBound)
            if !line.isEmpty { handleCompletedReply(line) }
        }
        // Guard against a device that streams without ever sending a prompt: never let an
        // un-terminated buffer grow without bound.
        if buffer.utf8.count > 4096 { buffer.removeAll(keepingCapacity: true) }
    }

    private func handleCompletedReply(_ line: String) {
        guard inFlightCommand != nil else { return }
        invalidateTimeout()
        switch connectionState {
        case .resetting, .configuring:
            apply(handshake.handle(.reply(line)))
        case .polling:
            if let reading = OBDPIDDecoder.decode(line) {
                store(reading)
                consecutivePollTimeouts = 0
            }
            advancePoll()
        default:
            break
        }
    }

    private func onTimeout() {
        inFlightCommand = nil
        switch connectionState {
        case .resetting, .configuring:
            apply(handshake.handle(.timeout))
        case .polling:
            consecutivePollTimeouts += 1
            if consecutivePollTimeouts >= maxPollTimeouts { degrade(); return }
            advancePoll()
        default:
            break
        }
    }

    // MARK: Handshake + polling

    private func beginHandshake() {
        transition(.resetting, "Bluetooth paired. Waking the OBD command processor…")
        transmit(handshake.openingCommand, timeout: 3.0) // ATZ can be slow
    }

    private func apply(_ action: ELM327Handshake.Action) {
        switch action {
        case .send(let command):
            transition((handshake.step == .reset) ? .resetting : .configuring,
                       handshake.step == .reset ? "Retrying adapter wake-up…" : "Negotiating the vehicle protocol…")
            transmit(command, timeout: 1.5)
        case .ready:
            captureProfile()      // bring-up (incl. ELM327 identity check) succeeded
            transition(.ready, "Adapter verified. Starting measured PIDs…")
            startPolling()
        case .failed:
            degrade("The device answered, but its OBD command processor could not be verified.",
                    recovery: "Power-cycle the adapter. GarageHUD supports ELM327, STN, and OBDLink CX command sets.")
        }
    }

    /// Once bring-up succeeds, record exactly what we connected to so the app can persist it
    /// and reconnect only to this validated device next time.
    private func captureProfile() {
        guard let peripheral, let writeChar, let notifyChar, let service = pairedServiceUUID else { return }
        // Prefer a clean catalog name (e.g. "OBDLink CX") over whatever the peripheral advertises.
        let name = KnownOBDAdapter.match(advertisedName: peripheral.name)?.displayName
            ?? peripheral.name ?? "OBD-II Adapter"
        discoveredProfile = OBDAdapterProfile(
            peripheralID: peripheral.identifier,
            name: name,
            serviceUUID: service,
            writeCharUUID: writeChar.uuid.uuidString,
            notifyCharUUID: notifyChar.uuid.uuidString,
            writeWithoutResponse: writeChar.properties.contains(.writeWithoutResponse),
            lastConnected: Date())
        if let discoveredProfile { OBDAdapterProfileStore.save(discoveredProfile) }
    }

    private func startPolling() {
        pidCursor = 0
        consecutivePollTimeouts = 0
        reconnectAttempts = 0   // a clean link resets the give-up counter
        transition(.polling, "Measured data is live")
        pollCurrent()
    }

    private func pollCurrent() {
        guard connectionState == .polling else { return }
        transmit(pids[pidCursor].rawValue, timeout: 1.0)
    }

    private func advancePoll() {
        pidCursor += 1
        if pidCursor >= pids.count {
            pidCursor = 0
            emitFrame() // one full cycle done
        }
        pollCurrent()
    }

    private func store(_ reading: OBDReading) {
        let m = TimedMeasurement(reading.value, source: .obdAdapter, at: Date())
        switch reading.pid {
        case .engineRPM: rpm = m
        case .vehicleSpeed: speedMph = m
        case .coolantTemp: coolant = m
        case .throttlePosition: throttle = m
        case .intakeManifoldPressure: boost = m
        }
    }

    private func degrade(_ message: String = "Adapter responses stopped",
                         recovery: String? = "GarageHUD will reconnect automatically.") {
        transition(.degraded, message, recovery: recovery)
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        // Bounded retries with linear backoff. Without this, a wrong/incompatible adapter
        // (e.g. one that fails the ELM327 identity check) would loop forever: reconnect →
        // rediscover the same device → fail → reconnect… draining the battery silently.
        reconnectAttempts += 1
        guard reconnectAttempts <= maxReconnectAttempts else {
            transition(.disconnected, "Adapter did not recover after \(maxReconnectAttempts) attempts",
                       recovery: "Power-cycle the adapter, close other OBD apps, then start a new session.")
            return
        }
        transition(.reconnecting, "Link interrupted. Reconnect \(reconnectAttempts) of \(maxReconnectAttempts)…",
                   recovery: "Keep the ignition on; GarageHUD is retrying.", attempt: reconnectAttempts)
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        let delay = min(2.0 * Double(reconnectAttempts), 10.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.stopped, self.central?.state == .poweredOn else { return }
            self.resetMeasurements()
            if let central = self.central {
                self.beginScan(central, message: "Looking for \(self.adapterName ?? "the adapter") again…")
            }
        }
    }

    /// Whether a discovered peripheral is plausibly an OBD adapter, so an unfiltered scan can still
    /// be safe. Accepts on: an advertised service UUID we know, a catalogued adapter name (OBDLink
    /// CX, ELM327 clones…), or any local name containing "obd". Pure so it's unit-testable.
    static func isLikelyOBDAdapter(advertisedName: String?, advertisedServiceUUIDs: [CBUUID],
                                   serviceUUIDs: [CBUUID]) -> Bool {
        if advertisedServiceUUIDs.contains(where: serviceUUIDs.contains) { return true }
        if let name = advertisedName {
            if KnownOBDAdapter.match(advertisedName: name)?.isBLE == true { return true }
            if name.lowercased().contains("obd") { return true }
        }
        return false
    }

    private func looksLikeOBDAdapter(_ peripheral: CBPeripheral, _ advertisementData: [String: Any]) -> Bool {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        let uuids = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        return Self.isLikelyOBDAdapter(advertisedName: name, advertisedServiceUUIDs: uuids,
                                       serviceUUIDs: serviceUUIDs)
    }

    private func emitFrame() {
        continuation.yield(LiveTelemetryFrame(
            rpm: rpm, speedMph: speedMph, coolantTempF: coolant,
            boostPsi: boost, throttlePercent: throttle,
            connectionState: connectionState, connectionDetail: connectionDetail, capturedAt: Date()))
    }
}

extension OBDLiveDataSource: CBCentralManagerDelegate, CBPeripheralDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopped else { return }
        if central.state == .poweredOn {
            if let knownPeripheralID,
               let saved = central.retrievePeripherals(withIdentifiers: [knownPeripheralID]).first {
                connect(saved, using: central, name: adapterName ?? saved.name)
            } else {
                beginScan(central)
            }
        } else {
            let detail: (String, String)
            switch central.state {
            case .unauthorized:
                detail = ("Bluetooth access is not allowed",
                          "Enable GarageHUD in iPhone Settings › Privacy & Security › Bluetooth.")
            case .poweredOff:
                detail = ("Bluetooth is turned off", "Turn Bluetooth on, then restart the Live session.")
            case .unsupported:
                detail = ("Bluetooth LE is unavailable on this device", "Use a Bluetooth LE-capable iPhone.")
            default:
                detail = ("Bluetooth is not ready", "Wait a moment, then restart the Live session.")
            }
            transition(.disconnected, detail.0, recovery: detail.1)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        // Reconnecting to a validated device: only that exact peripheral.
        if let known = knownPeripheralID {
            guard peripheral.identifier == known else { return }
        } else {
            // Fresh pairing on an unfiltered scan: connect only to something that actually looks
            // like an OBD adapter — by advertised service UUID, a known adapter name, or an
            // OBD-ish local name — so we never grab an unrelated Bluetooth device (headphones etc.).
            guard looksLikeOBDAdapter(peripheral, advertisementData) else { return }
        }
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
        connect(peripheral, using: central, name: name)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        linkToken += 1
        transition(.discoveringServices, "Bluetooth linked. Finding the OBDLink serial service…")
        peripheral.discoverServices(serviceUUIDs)
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral,
                               error: Error?) {
        linkToken += 1
        degrade("Bluetooth found \(adapterName ?? "the adapter"), but the link did not open.",
                recovery: "Close any other OBD app, power-cycle the adapter, and keep the ignition on.")
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            degrade("The adapter connected, but its services could not be read.")
            return
        }
        guard !(peripheral.services ?? []).isEmpty else {
            degrade("No supported OBD serial service was exposed.",
                    recovery: "GarageHUD expects OBDLink CX (FFF0) or a BLE ELM327 (FFE0).")
            return
        }
        transition(.discoveringCharacteristics, "Serial service found. Preparing secure notifications…")
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard connectionState == .discoveringCharacteristics else { return }
        guard error == nil else {
            degrade("The serial service was found, but its data channels could not be opened.")
            return
        }
        // Pair write + notify from the SAME service — never mix characteristics across services,
        // which could pick an unrelated pair on a multi-service adapter.
        let chars = service.characteristics ?? []
        let known = KnownOBDAdapter.match(advertisedName: adapterName)
        let notify = known?.notifyCharUUID.flatMap { expected in
            chars.first { $0.uuid == CBUUID(string: expected) && $0.properties.contains(.notify) }
        } ?? chars.first(where: { $0.properties.contains(.notify) })
        let write = known?.writeCharUUID.flatMap { expected in
            chars.first {
                $0.uuid == CBUUID(string: expected)
                    && ($0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write))
            }
        } ?? chars.first(where: { $0.properties.contains(.writeWithoutResponse) || $0.properties.contains(.write) })
        guard let notify, let write
        else { return } // this service isn't the serial one; wait for another's callback
        notifyChar = notify
        writeChar = write
        pairedServiceUUID = service.uuid.uuidString
        transition(.discoveringCharacteristics, "Serial channel ready. Waiting for iPhone pairing…",
                   recovery: "Approve the Bluetooth pairing prompt if one appears.")
        peripheral.setNotifyValue(true, for: notify)
    }

    public func peripheral(_ peripheral: CBPeripheral,
                           didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard characteristic.uuid == notifyChar?.uuid else { return }
        guard error == nil, characteristic.isNotifying else {
            degrade("iPhone could not subscribe to the adapter's data channel.",
                    recovery: "Power-cycle the OBDLink CX and approve the pairing prompt on the next attempt.")
            return
        }
        beginHandshake()
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil else {
            degrade("The adapter data channel reported an error.")
            return
        }
        guard let data = characteristic.value,
              let text = String(data: data, encoding: .ascii) else { return }
        ingest(text)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        invalidateTimeout()
        guard !stopped else { return }
        guard connectionState != .reconnecting else { return }
        transition(.degraded, "Bluetooth link closed unexpectedly",
                   recovery: "GarageHUD will reconnect automatically.")
        scheduleReconnect()
    }
}

#endif
