import Foundation

/// What a raw ELM327 response chunk reveals about *who answered and how* — not what they said.
///
/// W-069. The connection report could say a vehicle answered, but never whether one ECU answered or
/// several, or whether a reply arrived as a multi-frame (ISO-TP) transfer. So a Tundra session on
/// 2026-07-20 came back indistinguishable from a single-ECU car, and the multi-ECU criterion was
/// unmeasured rather than passed or failed.
///
/// This is derived **passively**, from bytes the proven bring-up already receives. No `ATDPN`, no
/// extra probe, nothing added to a handshake proven across three field sessions — the re-entry brief
/// is explicit about not destabilizing it, and observation should never cost stability.
///
/// The signals, given the app configures headers off (`ATH0`):
///   • several data lines answering one request → more than one responder on the bus,
///   • lines prefixed `0:` `1:` `2:` → the ELM's segmented form for a multi-frame transfer.
///
/// Deliberately reports what was *seen*. Absence is not proof of a single-ECU vehicle: a car may
/// simply not have been asked anything that provokes a multi-frame reply.
public struct OBDResponseShape: Equatable, Sendable {

    /// Data lines in the chunk that look like a mode-01 reply.
    public let dataLineCount: Int
    /// A segmented multi-frame transfer was present.
    public let isSegmented: Bool

    /// More than one responder answered a single request.
    public var isMultiResponder: Bool { dataLineCount > 1 }

    /// Worth recording in the connection journal — the plain case is not.
    public var isNoteworthy: Bool { isMultiResponder || isSegmented }

    public static func analyze(_ raw: String) -> OBDResponseShape {
        var dataLines = 0
        var segmented = false
        for piece in raw.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
            let line = piece.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if isSegmentMarker(line) { segmented = true; continue }
            if OBDPIDDecoder.decodeLine(line) != nil { dataLines += 1 }
        }
        return OBDResponseShape(dataLineCount: dataLines, isSegmented: segmented)
    }

    /// The ELM prints multi-frame payloads as `0:`, `1:`, `2:` … — a single hex digit, then a colon.
    /// Checked before decoding so a segment line is never miscounted as an independent responder.
    private static func isSegmentMarker(_ line: String) -> Bool {
        guard let colon = line.firstIndex(of: ":") else { return false }
        let prefix = line[line.startIndex..<colon]
        return !prefix.isEmpty && prefix.count <= 2
            && prefix.allSatisfy { $0.isHexDigit }
    }

    /// One line for the connection report, in the report's plain-language register.
    public var journalMessage: String {
        switch (isMultiResponder, isSegmented) {
        case (true, true):
            return "\(dataLineCount) control units answered, and a reply arrived as a multi-frame transfer"
        case (true, false):
            return "\(dataLineCount) control units answered the same request"
        case (false, true):
            return "A reply arrived as a multi-frame transfer"
        case (false, false):
            return "Single control unit, single-frame replies"
        }
    }
}
