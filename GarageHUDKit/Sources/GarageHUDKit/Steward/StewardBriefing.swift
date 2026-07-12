import Foundation

/// One line of a briefing — an observation plus which car it belongs to (nil = fleet-level).
public struct StewardBriefingItem: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public let vehicleName: String?
    public let observation: StewardObservation
    public static func == (l: StewardBriefingItem, r: StewardBriefingItem) -> Bool { l.id == r.id }
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

    public static func build(for vehicles: [Vehicle], mode: DrivingMode = .parked, limit: Int = 5) -> StewardBriefing {
        var pool: [StewardBriefingItem] = []

        // Fleet-level first — these are the cross-car insights nothing else surfaces.
        for obs in Steward.observeFleet(vehicles) {
            pool.append(StewardBriefingItem(vehicleName: nil, observation: obs))
        }
        // Each car contributes its top two observations; ranking below sorts the whole pool.
        for vehicle in vehicles {
            for obs in Steward.observe(vehicle).prefix(2) {
                pool.append(StewardBriefingItem(vehicleName: vehicle.displayName, observation: obs))
            }
        }

        // While moving, drop everything that isn't a genuine advisory.
        if mode == .moving {
            pool = pool.filter { $0.observation.tone == .advisory }
        }

        let ranked = pool.sorted { rank($0.observation) > rank($1.observation) }
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
                lines.append("\(body) Confidence \(item.observation.confidence) percent.")
            }
        }
        return lines.joined(separator: " ")
    }

    // MARK: Helpers

    private static func rank(_ o: StewardObservation) -> Int {
        switch o.tone {
        case .advisory: return 200 + o.confidence
        case .caution: return 100 + o.confidence
        case .informational: return o.confidence
        }
    }

    private static func firstSentence(_ text: String) -> String {
        (text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true).first.map { String($0) + "." }) ?? text
    }

    private static func lowercasingFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }
}
