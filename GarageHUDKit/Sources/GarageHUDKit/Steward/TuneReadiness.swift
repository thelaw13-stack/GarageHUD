import Foundation

/// An evidence-based pre-pull decision for the current recorded setup. This does not invent an
/// ECU calibration or claim mechanical safety; it checks whether the build record, operating
/// envelope, and latest validation data agree well enough to proceed deliberately.
public struct TuneReadiness: Equatable, Sendable {
    public enum State: Int, Equatable, Sendable {
        case ready
        case verify
        case hold

        public var label: String {
            switch self {
            case .ready: return "Ready"
            case .verify: return "Verify"
            case .hold: return "Hold"
            }
        }
    }

    public struct Check: Identifiable, Equatable, Sendable {
        public let id: String
        public let title: String
        public let detail: String
        public let state: State

        public init(id: String, title: String, detail: String, state: State) {
            self.id = id
            self.title = title
            self.detail = detail
            self.state = state
        }
    }

    public let state: State
    public let headline: String
    public let checks: [Check]
    public let confidence: ConfidenceBand

    public var holdCount: Int { checks.filter { $0.state == .hold }.count }
    public var verifyCount: Int { checks.filter { $0.state == .verify }.count }
    public var readyCount: Int { checks.filter { $0.state == .ready }.count }
}

public extension Steward {
    static func tuneReadiness(_ vehicle: Vehicle, context: StewardContext = .live) -> TuneReadiness {
        var checks: [TuneReadiness.Check] = []
        // Two distinct gates (W-045): support scrutiny applies when the boost is turned UP
        // (aftermarket FI, or a tuned/over-stock factory platform); a boost target map is
        // legitimate on ANY car that makes boost — including a bone-stock factory turbo.
        let elevated = vehicle.runsElevatedBoost
        let makesBoost = vehicle.runsBoost
        let envelope = vehicle.operatingEnvelope

        checks.append(serviceCheck(vehicle, context: context))
        if elevated {
            checks.append(supportCheck(vehicle, category: .fueling, title: "Fuel delivery",
                                       role: "Fueling support is recorded for the current air load."))
            checks.append(supportCheck(vehicle, category: .cooling, title: "Thermal control",
                                       role: "Cooling support is recorded for repeated loaded operation."))
        }
        checks.append(calibrationCheck(vehicle))
        checks.append(dynoCheck(vehicle))
        if !vehicle.pullReports.isEmpty {
            checks.append(pullHistoryCheck(vehicle.pullReports))
        }

        if makesBoost {
            checks.append(contentsOf: boostProfileChecks(envelope))
        } else if envelope.boostCautionPsi != nil || envelope.maxSustainedBoostPsi != nil
                    || !envelope.expectedBoostByRPM.isEmpty {
            checks.append(.init(
                id: "profile.unexpectedBoost",
                title: "Boost profile",
                detail: "Boost targets are configured, but nothing on record says this car makes boost.",
                state: .hold))
        } else {
            checks.append(.init(
                id: "profile.na",
                title: "Load profile",
                detail: "No boost map is required for the naturally aspirated setup on record.",
                state: .ready))
        }

        let state: TuneReadiness.State
        if checks.contains(where: { $0.state == .hold }) {
            state = .hold
        } else if checks.contains(where: { $0.state == .verify }) {
            state = .verify
        } else {
            state = .ready
        }

        let headline: String
        switch state {
        case .ready:
            headline = "The recorded setup and tune envelope agree. Start conservatively and watch live limits."
        case .verify:
            let count = checks.filter { $0.state == .verify }.count
            headline = "Verify \(count) item\(count == 1 ? "" : "s") before a committed pull."
        case .hold:
            let count = checks.filter { $0.state == .hold }.count
            headline = "Hold the pull until \(count) conflict\(count == 1 ? " is" : "s are") resolved."
        }

        let confidence: ConfidenceBand
        if checks.contains(where: { $0.id.hasPrefix("support.") && $0.state == .verify }) {
            confidence = .moderate
        } else if vehicle.parts.isEmpty {
            confidence = .weak
        } else {
            confidence = .strong
        }

        return TuneReadiness(state: state, headline: headline, checks: checks, confidence: confidence)
    }

    private static func serviceCheck(_ vehicle: Vehicle, context: StewardContext) -> TuneReadiness.Check {
        if vehicle.serviceStatus.isInService {
            let reason = vehicle.serviceStatus.reason.isEmpty ? "The vehicle is marked out of service." : vehicle.serviceStatus.reason
            return .init(id: "condition.outOfService", title: "Vehicle condition", detail: reason, state: .hold)
        }
        guard !vehicle.maintenance.isEmpty else {
            return .init(id: "condition.noSchedule", title: "Vehicle condition",
                         detail: "No maintenance schedule is recorded; confirm fluids and inspection status manually.", state: .verify)
        }
        switch vehicle.maintenanceDue(now: context.now, calendar: context.calendar) {
        case .overdue:
            return .init(id: "condition.overdue", title: "Vehicle condition",
                         detail: "At least one service item is overdue. Resolve it before a loaded pull.", state: .hold)
        case .dueSoon:
            return .init(id: "condition.dueSoon", title: "Vehicle condition",
                         detail: "A service item is due soon; verify it is suitable for the planned session.", state: .verify)
        case .ok:
            return .init(id: "condition.current", title: "Vehicle condition",
                         detail: "Recorded maintenance is current.", state: .ready)
        }
    }

    private static func supportCheck(_ vehicle: Vehicle, category: PartCategory, title: String,
                                     role: String) -> TuneReadiness.Check {
        switch vehicle.knowledge(of: category) {
        case .confirmedPresent:
            return .init(id: "support.\(category.rawValue)", title: title, detail: role, state: .ready)
        case .confirmedAbsent:
            return .init(id: "support.\(category.rawValue)", title: title,
                         detail: "This system is confirmed factory-stock; verify its capacity against the requested load.", state: .hold)
        case .undocumented, .unknown:
            return .init(id: "support.\(category.rawValue)", title: title,
                         detail: "Capacity is not documented for the current setup.", state: .verify)
        }
    }

    private static func calibrationCheck(_ vehicle: Vehicle) -> TuneReadiness.Check {
        // Shared with the elevated-boost gate (Vehicle.calibrationTerms), so "is there a tune
        // on record?" has exactly one definition.
        if let calibration = vehicle.calibrationPartOnRecord {
            return .init(id: "calibration.recorded", title: "Calibration record",
                         detail: "\(calibration.name) is recorded on the current setup.", state: .ready)
        }
        return .init(id: "calibration.missing", title: "Calibration record",
                     detail: "No ECU, map, flash, or professional tune is identified in installed electronics.", state: .verify)
    }

    private static func dynoCheck(_ vehicle: Vehicle) -> TuneReadiness.Check {
        guard let dynoDate = vehicle.latestDynoDate else {
            return .init(id: "validation.noDyno", title: "Current validation",
                         detail: "No wheel-power dyno is recorded for this setup.", state: .verify)
        }
        let loadBearing: Set<PartCategory> = [.engine, .forcedInduction, .fueling, .cooling, .exhaust, .electronics]
        if let change = vehicle.latestInstall(inAny: loadBearing), change.date > dynoDate {
            return .init(id: "validation.staleDyno", title: "Current validation",
                         detail: "\(change.part.name) was installed after the latest dyno; the recorded result describes older hardware.",
                         state: .hold)
        }
        return .init(id: "validation.currentDyno", title: "Current validation",
                     detail: "No dated powertrain change appears after the latest dyno.", state: .ready)
    }

    private static func pullHistoryCheck(_ reports: [PullReport]) -> TuneReadiness.Check {
        let intelligence = PullIntelligence.analyze(reports)
        let state: TuneReadiness.State
        switch intelligence.state {
        case .hold: state = .hold
        case .watch, .learning: state = .verify
        case .stable: state = .ready
        }
        return .init(
            id: "validation.pullHistory",
            title: "Recent pull behavior",
            detail: "\(intelligence.headline) \(intelligence.evidence)",
            state: state)
    }

    private static func boostProfileChecks(_ envelope: OperatingEnvelope) -> [TuneReadiness.Check] {
        let bands = envelope.expectedBoostByRPM.sorted { $0.rpmLow < $1.rpmLow }
        guard !bands.isEmpty else {
            return [.init(id: "profile.noBands", title: "RPM boost targets",
                          detail: "No RPM-banded target map is entered; Live can only judge a generic threshold.", state: .verify)]
        }

        var checks: [TuneReadiness.Check] = []
        let malformed = bands.contains {
            $0.rpmLow >= $0.rpmHigh || $0.expectedLowPsi < 0 || $0.expectedLowPsi > $0.expectedHighPsi
        }
        checks.append(.init(
            id: "profile.ranges",
            title: "Target ranges",
            detail: malformed
                ? "At least one RPM or boost range is inverted or invalid."
                : "All \(bands.count) target band\(bands.count == 1 ? "" : "s") use valid RPM and boost ranges.",
            state: malformed ? .hold : .ready))

        let pairs = zip(bands, bands.dropFirst())
        let overlap = pairs.contains { prior, next in next.rpmLow <= prior.rpmHigh }
        checks.append(.init(
            id: "profile.continuity",
            title: "Map continuity",
            detail: overlap
                ? "RPM bands overlap, so one engine speed can produce conflicting targets."
                : profileGapDetail(bands),
            state: overlap ? .hold : (hasLargeGap(bands) ? .verify : .ready)))

        let highestTarget = bands.map(\.expectedHighPsi).max() ?? 0
        if let ceiling = envelope.maxSustainedBoostPsi {
            checks.append(.init(
                id: "profile.ceiling",
                title: "Boost ceiling",
                detail: ceiling < highestTarget
                    ? "The \(format(ceiling)) psi ceiling is below the \(format(highestTarget)) psi target requested by the map."
                    : "The \(format(ceiling)) psi ceiling stays above every entered target.",
                state: ceiling < highestTarget ? .hold : .ready))
        } else {
            checks.append(.init(id: "profile.noCeiling", title: "Boost ceiling",
                                detail: "No hard over-boost ceiling is configured.", state: .verify))
        }
        return checks
    }

    private static func hasLargeGap(_ bands: [BoostBand]) -> Bool {
        zip(bands, bands.dropFirst()).contains { prior, next in next.rpmLow - prior.rpmHigh > 250 }
    }

    private static func profileGapDetail(_ bands: [BoostBand]) -> String {
        if hasLargeGap(bands) {
            return "The target map leaves more than 250 RPM uncovered between bands."
        }
        return "Target bands are ordered without overlap or a material RPM gap."
    }

    private static func format(_ value: Double) -> String { String(format: "%g", value) }
}

/// A concrete way to resolve a readiness check — so a "verify"/"hold" isn't just a diagnosis but a
/// door to fix it. Pure mapping from the check id; the Tuner view routes or acts on it.
public enum TuneAction: Equatable, Sendable {
    case resolveMaintenance                 // overdue / due-soon / no schedule → the service panel
    case returnToService                    // the car is out of service
    case confirmSupport(PartCategory)       // fueling/cooling not documented → confirm stock or log it
    case documentEngine                     // no calibration/engine detail recorded
    case confirmForcedInduction             // boost map set but FI not confirmed in the parts record
    case logDyno                            // no / stale dyno validation
    case editBoostMap                       // the RPM boost target map needs work (in-page)

    /// The short button label shown on the check row.
    public var label: String {
        switch self {
        case .resolveMaintenance: return "Service"
        case .returnToService: return "Status"
        case .confirmSupport: return "Confirm"
        case .documentEngine: return "Add specs"
        case .confirmForcedInduction: return "Fix specs"
        case .logDyno: return "Log dyno"
        case .editBoostMap: return "Edit map"
        }
    }
}

public extension TuneReadiness.Check {
    /// The action that resolves this check, or nil when it's already satisfied (`.ready`) or purely
    /// informational. Actionable only for the `verify`/`hold` items the owner asked to be able to act on.
    var action: TuneAction? {
        guard state != .ready else { return nil }
        if id == "condition.outOfService" { return .returnToService }
        if id.hasPrefix("condition.") { return .resolveMaintenance }         // overdue / dueSoon / noSchedule
        if id.hasPrefix("support.") {
            return PartCategory(rawValue: String(id.dropFirst("support.".count))).map { .confirmSupport($0) }
        }
        if id == "calibration.missing" { return .documentEngine }
        if id.hasPrefix("validation.") && (id.contains("noDyno") || id.contains("staleDyno")) { return .logDyno }
        if id == "profile.unexpectedBoost" { return .confirmForcedInduction }
        if id.hasPrefix("profile.") { return .editBoostMap }                  // bands / ranges / continuity / ceiling
        return nil
    }
}
