import Foundation

/// The five standard OBD-II Mode 01 PIDs the Live HUD reads. Raw values are the ELM327
/// request strings ("01" = current-data mode, then the PID byte).
public enum OBDPID: String, CaseIterable, Sendable {
    case engineRPM          = "010C"
    case vehicleSpeed       = "010D"
    case coolantTemp        = "0105"
    case throttlePosition   = "0111"
    // Baro is declared before MAP so the poll rotation (which follows allCases order) measures
    // ambient pressure before the first boost computation needs it.
    case barometricPressure = "0133"
    case intakeManifoldPressure = "010B"

    /// The response header a valid reply carries: 0x41 (0x01 + 0x40) followed by the PID byte.
    /// e.g. request "010C" → response begins "41 0C".
    var responsePIDByte: UInt8 { UInt8(rawValue.suffix(2), radix: 16) ?? 0 }
}

/// One decoded reading, already converted into the unit `LiveMetrics` uses.
public struct OBDReading: Equatable, Sendable {
    public let pid: OBDPID
    public let value: Double
    public init(pid: OBDPID, value: Double) {
        self.pid = pid
        self.value = value
    }
}

/// Turns raw ELM327 responses into physical values. This is the honest core of live
/// telemetry: no estimation, just the SAE J1979 formulas applied to the bytes the ECU
/// actually returned. Pure and synchronous so every conversion is unit-tested; the
/// Bluetooth transport merely feeds it lines.
public enum OBDPIDDecoder {

    /// Decode an ELM327 response chunk. A chunk can carry several lines before the prompt —
    /// on the very first queries the data arrives WITH a status marker in the same chunk
    /// ("SEARCHING...\r41 0C 1A F8"). Decoding is per-line, so markers are skipped, never
    /// fatal: the whole first driveway session (W-052) was lost to a decoder that discarded
    /// any chunk containing "SEARCHING" — including the valid data right after it.
    /// Returns nil only when NO line in the chunk decodes.
    public static func decode(_ raw: String) -> OBDReading? {
        raw.split(whereSeparator: { $0 == "\r" || $0 == "\n" })
            .lazy
            .compactMap { decodeLine(String($0)) }
            .first
    }

    /// Decode one response line ("41 0C 1A F8" / "410C1AF8", possibly with a trailing ">").
    /// Nil for status/error lines ("NO DATA", "SEARCHING...") and unknown PIDs.
    static func decodeLine(_ raw: String) -> OBDReading? {
        let bytes = hexBytes(raw)
        // A valid reply is: 0x41, <pid>, <data...>. Find the mode byte and read from there.
        guard let modeIndex = bytes.firstIndex(of: 0x41), bytes.count > modeIndex + 1 else { return nil }
        let pidByte = bytes[modeIndex + 1]
        let data = Array(bytes[(modeIndex + 2)...])
        guard let pid = OBDPID.allCases.first(where: { $0.responsePIDByte == pidByte }) else { return nil }

        func a() -> Double? { data.first.map(Double.init) }
        func b() -> Double? { data.count > 1 ? Double(data[1]) : nil }

        switch pid {
        case .engineRPM:
            guard let A = a(), let B = b() else { return nil }
            return OBDReading(pid: pid, value: (256 * A + B) / 4)              // rpm
        case .vehicleSpeed:
            guard let A = a() else { return nil }
            return OBDReading(pid: pid, value: A * 0.621371)                   // km/h → mph
        case .coolantTemp:
            guard let A = a() else { return nil }
            return OBDReading(pid: pid, value: (A - 40) * 9 / 5 + 32)          // °C → °F
        case .throttlePosition:
            guard let A = a() else { return nil }
            return OBDReading(pid: pid, value: A * 100 / 255)                  // %
        case .barometricPressure:
            guard let A = a() else { return nil }
            return OBDReading(pid: pid, value: A)                              // kPa, absolute
        case .intakeManifoldPressure:
            guard let A = a() else { return nil }
            // Raw manifold absolute pressure in kPa. Gauge boost is MAP minus the *measured*
            // barometric pressure (`gaugeBoostPsi`) — subtracting a hardcoded sea-level constant
            // here would make "measured" boost silently wrong by ~2.7 psi in Denver.
            return OBDReading(pid: pid, value: A)                              // kPa, absolute
        }
    }

    /// Standard atmosphere, used only when the vehicle hasn't answered the baro PID yet.
    public static let seaLevelKPa = 101.325

    /// Gauge boost from manifold absolute pressure and barometric pressure, both kPa.
    /// Negative under vacuum, which is physically correct off-throttle.
    public static func gaugeBoostPsi(mapKPa: Double, baroKPa: Double) -> Double {
        (mapKPa - baroKPa) * 0.145038                                          // kPa → psi
    }

    /// Extract hex byte values from a raw ELM327 line, ignoring spaces, the ">" prompt, and
    /// any non-hex noise. Returns [] for lines with no usable hex (so callers get nil).
    static func hexBytes(_ raw: String) -> [UInt8] {
        let upper = raw.uppercased()
        // Bail on the known non-data replies before trying to read hex out of them.
        for marker in ["NO DATA", "SEARCHING", "UNABLE", "STOPPED", "ERROR", "?"] where upper.contains(marker) {
            return []
        }
        let hexChars = upper.filter { $0.isHexDigit }
        guard hexChars.count >= 2 else { return [] }
        var bytes: [UInt8] = []
        var iterator = hexChars.makeIterator()
        while let hi = iterator.next(), let lo = iterator.next() {
            if let byte = UInt8("\(hi)\(lo)", radix: 16) { bytes.append(byte) }
        }
        return bytes
    }
}
