import Foundation

#if canImport(CoreBluetooth)
import CoreBluetooth

/// A real OBD-II feed over a Bluetooth-LE ELM327 adapter. Conforms to the same
/// `LiveDataSource` the Live HUD already consumes, so swapping it in for the simulator
/// changes nothing on screen — except that the numbers are now measured, not invented.
///
/// It connects to the adapter, runs the standard ELM327 init handshake, then round-robins
/// the five PIDs, decoding each reply through the pure `OBDPIDDecoder` and emitting a
/// `LiveMetrics` frame each cycle. The decoding math is tested; this shell is the plumbing.
///
/// Common BLE ELM327 clones expose a serial service on FFF0 (chars FFF1/FFF2) or FFE0
/// (FFE1); both are probed. `isConnected` lets the UI reflect link state honestly.
public final class OBDLiveDataSource: NSObject, LiveDataSource {

    public let metricsStream: AsyncStream<LiveMetrics>
    private let continuation: AsyncStream<LiveMetrics>.Continuation

    /// Reflects real link state so the HUD never claims "measured" while disconnected.
    public private(set) var isConnected = false

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var notifyChar: CBCharacteristic?

    private let serviceUUIDs: [CBUUID] = [CBUUID(string: "FFF0"), CBUUID(string: "FFE0")]

    // Assembled from whatever PIDs have most recently replied.
    private var rpm = 0.0, speed = 0.0, coolantF = 175.0, boostPsi = 0.0, throttle = 0.0
    private var buffer = ""
    private var pollTask: Task<Void, Never>?
    private var handshakeDone = false

    public override init() {
        var captured: AsyncStream<LiveMetrics>.Continuation!
        self.metricsStream = AsyncStream { captured = $0 }
        self.continuation = captured
        super.init()
    }

    public func start() {
        central = CBCentralManager(delegate: self, queue: nil)
    }

    public func stop() {
        pollTask?.cancel(); pollTask = nil
        if let peripheral, let central { central.cancelPeripheralConnection(peripheral) }
        isConnected = false
        continuation.finish()
    }

    // MARK: ELM327 protocol

    private func send(_ command: String) {
        guard let peripheral, let writeChar,
              let data = (command + "\r").data(using: .ascii) else { return }
        peripheral.writeValue(data, for: writeChar, type: .withoutResponse)
    }

    /// Standard ELM327 bring-up: reset, echo off, linefeeds off, headers off, auto protocol.
    private func runHandshake() {
        for cmd in ["ATZ", "ATE0", "ATL0", "ATH0", "ATSP0"] { send(cmd) }
        handshakeDone = true
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isConnected else { break }
                for pid in OBDPID.allCases {
                    self.send(pid.rawValue)
                    try? await Task.sleep(nanoseconds: 60_000_000) // ~60ms between PIDs
                }
                self.emitFrame()
            }
        }
    }

    private func emitFrame() {
        continuation.yield(LiveMetrics(
            rpm: rpm, speedMph: speed, coolantTempF: coolantF,
            boostPsi: boostPsi, throttlePercent: throttle))
    }

    /// Fold incoming bytes; ELM327 terminates a reply with ">". Decode each complete line.
    private func ingest(_ text: String) {
        buffer += text
        while let range = buffer.range(of: ">") {
            let line = String(buffer[..<range.lowerBound])
            buffer.removeSubrange(..<range.upperBound)
            apply(line)
        }
    }

    private func apply(_ line: String) {
        guard let reading = OBDPIDDecoder.decode(line) else { return }
        switch reading.pid {
        case .engineRPM: rpm = reading.value
        case .vehicleSpeed: speed = reading.value
        case .coolantTemp: coolantF = reading.value
        case .throttlePosition: throttle = reading.value
        case .intakeManifoldPressure: boostPsi = reading.value
        }
    }
}

extension OBDLiveDataSource: CBCentralManagerDelegate, CBPeripheralDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: serviceUUIDs)
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                               advertisementData: [String: Any], rssi RSSI: NSNumber) {
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices(serviceUUIDs)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
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
        if writeChar != nil, notifyChar != nil, !handshakeDone {
            isConnected = true
            runHandshake()
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let data = characteristic.value, let text = String(data: data, encoding: .ascii) else { return }
        ingest(text)
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        handshakeDone = false
    }
}

#endif
