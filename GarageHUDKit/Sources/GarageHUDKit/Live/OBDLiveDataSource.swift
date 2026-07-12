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

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?
    private let serviceUUIDs: [CBUUID] = [CBUUID(string: "FFF0"), CBUUID(string: "FFE0")]

    private var handshake = ELM327Handshake()
    private let pids = OBDPID.allCases
    private var pidCursor = 0
    private var consecutivePollTimeouts = 0
    private let maxPollTimeouts = OBDPID.allCases.count + 2

    // In-flight command tracking — exactly one at a time, prompt-gated.
    private var buffer = ""
    private var inFlightCommand: String?
    private var timeoutToken = 0
    private var stopped = true

    // Per-metric measurements, each stamped when its reply actually arrives.
    private var rpm, speedMph, coolant, boost, throttle: TimedMeasurement<Double>?

    public override init() {
        var captured: AsyncStream<LiveTelemetryFrame>.Continuation!
        self.frames = AsyncStream { captured = $0 }
        self.continuation = captured
        super.init()
    }

    deinit { continuation.finish() }

    // MARK: Lifecycle

    public func start() {
        stopped = false
        resetMeasurements()
        connectionState = .scanning
        central = CBCentralManager(delegate: self, queue: .main) // confine callbacks to main
    }

    public func stop() {
        stopped = true
        invalidateTimeout()
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        central?.stopScan()
        connectionState = .disconnected
        // Stream stays open (reusable); deinit finishes it.
    }

    private func resetMeasurements() {
        rpm = nil; speedMph = nil; coolant = nil; boost = nil; throttle = nil
        pidCursor = 0; consecutivePollTimeouts = 0; handshake = ELM327Handshake()
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
        connectionState = .resetting
        transmit(handshake.openingCommand, timeout: 3.0) // ATZ can be slow
    }

    private func apply(_ action: ELM327Handshake.Action) {
        switch action {
        case .send(let command):
            connectionState = (handshake.step == .reset) ? .resetting : .configuring
            transmit(command, timeout: 1.5)
        case .ready:
            connectionState = .ready
            startPolling()
        case .failed:
            degrade()
        }
    }

    private func startPolling() {
        pidCursor = 0
        consecutivePollTimeouts = 0
        connectionState = .polling
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

    private func degrade() {
        connectionState = .degraded
        scheduleReconnect()
    }

    private func scheduleReconnect() {
        guard !stopped else { return }
        connectionState = .reconnecting
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, !self.stopped, self.central?.state == .poweredOn else { return }
            self.resetMeasurements()
            self.connectionState = .scanning
            self.central?.scanForPeripherals(withServices: self.serviceUUIDs)
        }
    }

    private func emitFrame() {
        continuation.yield(LiveTelemetryFrame(
            rpm: rpm, speedMph: speedMph, coolantTempF: coolant,
            boostPsi: boost, throttlePercent: throttle,
            connectionState: connectionState, capturedAt: Date()))
    }
}

extension OBDLiveDataSource: CBCentralManagerDelegate, CBPeripheralDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard !stopped else { return }
        if central.state == .poweredOn {
            connectionState = .scanning
            central.scanForPeripherals(withServices: serviceUUIDs)
        } else {
            connectionState = .disconnected
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        connectionState = .connecting
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .discoveringServices
        peripheral.discoverServices(serviceUUIDs)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else { degrade(); return }
        connectionState = .discoveringCharacteristics
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for char in service.characteristics ?? [] {
            if char.properties.contains(.notify) {
                notifyChar = char
                peripheral.setNotifyValue(true, for: char)
            }
            if char.properties.contains(.writeWithoutResponse) || char.properties.contains(.write) {
                writeChar = char
            }
        }
        // Begin bring-up only once, and only when we can both write and hear back.
        if writeChar != nil, notifyChar != nil,
           connectionState == .discoveringCharacteristics {
            beginHandshake()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value,
              let text = String(data: data, encoding: .ascii) else { return }
        ingest(text)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        invalidateTimeout()
        guard !stopped else { return }
        scheduleReconnect()
    }
}

#endif
