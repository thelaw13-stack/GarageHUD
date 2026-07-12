import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// One line of a briefing — an observation plus which car it belongs to (nil = fleet-level).
/// Identity is the observation's deterministic id, so an identical briefing rebuilds to
/// identical items and SwiftUI doesn't churn the diff.
public struct StewardBriefingItem: Identifiable, Equatable, Sendable {
    public let vehicleName: String?
    public let observation: StewardObservation
    public var id: String { observation.id }
    public static func == (l: StewardBriefingItem, r: StewardBriefingItem) -> Bool {
        l.observation.id == r.observation.id
    }
}

/// A ready-to-read (or ready-to-speak) rollup of what most deserves the owner's attention
/// right now, drawn from every reasoning layer at once: fleet comparisons and each car's
/// top observations, ranked together and capped so a briefing stays a briefing.
public struct StewardBriefing: Equatable, Sendable {
    public let headline: String
    public let items: [StewardBriefingItem]
    public let spokenScript: String
}

/// Assembles the briefing. Pure and synchronous — the voice layer just speaks `spokenScript`,
/// the UI renders `items`. Honors driving mode: while moving, only the advisories survive and
/// the script stays terse.
public enum StewardBriefingBuilder {

    public static func build(for vehicles: [Vehicle], mode: DrivingMode = .parked,
                             limit: Int = 5, context: StewardContext = .live) -> StewardBriefing {
        var pool: [StewardBriefingItem] = []

        // Fleet-level first — these are the cross-car insights nothing else surfaces.
        for obs in Steward.observeFleet(vehicles, context: context) {
            pool.append(StewardBriefingItem(vehicleName: nil, observation: obs))
        }
        // Each car contributes its top two observations; ranking below sorts the whole pool.
        for vehicle in vehicles {
            for obs in Steward.observe(vehicle, context: context).prefix(2) {
                pool.append(StewardBriefingItem(vehicleName: vehicle.displayName, observation: obs))
            }
        }

        // While moving, drop everything that isn't a genuine advisory.
        if mode == .moving {
            pool = pool.filter { $0.observation.tone == .advisory }
        }

        // Deterministic order with explicit tie-breakers (matches Steward.ordered).
        let ranked = pool.sorted { a, b in
            if rank(a.observation) != rank(b.observation) { return rank(a.observation) > rank(b.observation) }
            if (a.vehicleName ?? "") != (b.vehicleName ?? "") { return (a.vehicleName ?? "") < (b.vehicleName ?? "") }
            return a.observation.ruleID < b.observation.ruleID
        }
        let items = Array(ranked.prefix(limit))

        return StewardBriefing(
            headline: headline(for: items, vehicleCount: vehicles.count, mode: mode),
            items: items,
            spokenScript: script(for: items, mode: mode))
    }

    // MARK: Copy

    private static func headline(for items: [StewardBriefingItem], vehicleCount: Int, mode: DrivingMode) -> String {
        guard !items.isEmpty else {
            return mode == .moving ? "Nothing urgent." : "Nothing pressing across the garage."
        }
        let cautionsUp = items.filter { $0.observation.tone != .informational }.count
        if cautionsUp == 0 { return "A few things worth noting." }
        let cars = vehicleCount == 1 ? "" : " across \(vehicleCount) cars"
        return "\(cautionsUp) thing\(cautionsUp == 1 ? "" : "s") for your attention\(cars)."
    }

    private static func script(for items: [StewardBriefingItem], mode: DrivingMode) -> String {
        guard !items.isEmpty else {
            return mode == .moving ? "Nothing urgent right now." : "Nothing pressing across the garage right now."
        }
        var lines: [String] = [mode == .moving ? "Quick briefing." : "Here's your garage briefing."]
        for item in items {
            let statement = firstSentence(item.observation.statement)
            let prefix = item.vehicleName.map { "On \($0), " } ?? ""
            // Lead-lowercase the statement when it follows an "On <car>," prefix.
            let body = prefix.isEmpty ? statement : prefix + lowercasingFirst(statement)
            if mode == .moving {
                lines.append(body)
            } else {
                lines.append("\(body) \(capitalizedFirst(item.observation.confidence.spokenPhrase)).")
            }
        }
        return lines.joined(separator: " ")
    }

    // MARK: Helpers

    private static func rank(_ o: StewardObservation) -> Int {
        switch o.tone {
        case .advisory: return 200 + o.confidence.rawValue
        case .caution: return 100 + o.confidence.rawValue
        case .informational: return o.confidence.rawValue
        }
    }

    /// First sentence via proper sentence segmentation — so "12.5 psi", abbreviations, and
    /// model names with punctuation don't get chopped mid-number the way a naive split on "."
    /// would. Falls back to the whole string if segmentation yields nothing.
    static func firstSentence(_ text: String) -> String {
        #if canImport(NaturalLanguage)
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var first: String?
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            first = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return false // stop after the first sentence
        }
        return first ?? text
        #else
        return text
        #endif
    }

    private static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
