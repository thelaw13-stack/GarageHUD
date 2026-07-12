import Foundation

/// Fleet Steward — the reasoning layer. GarageHUD owns memory; Steward interprets it.
///
/// Steward never owns truth and never manufactures urgency. It reads recorded data, emits
/// `StewardObservation`s that carry their own evidence and an honest evidence *band*, and
/// orders them deterministically so the most decision-relevant surfaces first. It distinguishes
/// what is *recorded* from what is merely *not recorded*: an undocumented subsystem is never
/// reported as a missing one. Every rule is a pure function of (model, `StewardContext`).
public enum Steward {

    // MARK: - Garage observations (reasoned over recorded memory)

    public static func observe(_ vehicle: Vehicle, context: StewardContext = .live) -> [StewardObservation] {
        var out: [StewardObservation] = []
        let vid = vehicle.id
        let hasForcedInduction = vehicle.knowledge(of: .forcedInduction) == .confirmedPresent

        // 1–2. Fueling and cooling should keep up with forced induction — phrased by what we
        //       actually know, never conflating "not logged" with "not installed".
        if hasForcedInduction {
            if let o = supportGap(vehicle, support: .fueling, subsystem: "fuel system",
                                  trigger: "Forced induction is installed.") { out.append(o) }
            if let o = supportGap(vehicle, support: .cooling, subsystem: "cooling",
                                  trigger: "Forced induction is installed.") { out.append(o) }
        }

        // 3. Braking should keep pace with power and grip.
        let powerUp = (vehicle.horsepowerGainedOverStock ?? 0) >= 40
        if vehicle.knowledge(of: .suspension) == .confirmedPresent || powerUp {
            let trigger = vehicle.knowledge(of: .suspension) == .confirmedPresent
                ? "Suspension is upgraded." : "Power is up meaningfully over stock."
            if let o = supportGap(vehicle, support: .brakes, subsystem: "brakes", trigger: trigger) { out.append(o) }
        }

        // 3b. Sequence hazard — boost dated before fueling support.
        if hasForcedInduction,
           let fiDate = vehicle.earliestInstall(in: .forcedInduction),
           let fuelDate = vehicle.earliestInstall(in: .fueling),
           fiDate < fuelDate {
            let days = context.days(from: fiDate, to: fuelDate)
            if days >= 14 {
                out.append(StewardObservation(
                    ruleID: "sequence.fiAheadOfFueling", subjectID: vid,
                    statement: "Based on your history, forced induction ran ahead of the fueling for a stretch.",
                    evidence: "Boost was installed \(short(fiDate)); fueling support followed \(days) days later (\(short(fuelDate))).",
                    confidence: .moderate, tone: .caution, provenance: .derived))
            }
        }

        // 3c. Stale tune — a powertrain part installed after the last dyno. A recorded fact.
        if let dyno = vehicle.latestDynoDate,
           let (part, hwDate) = vehicle.latestInstall(inAny: [.forcedInduction, .fueling, .engine, .exhaust]),
           hwDate > dyno {
            let days = context.days(from: dyno, to: hwDate)
            if days >= 7 {
                out.append(StewardObservation(
                    ruleID: "tune.stale", subjectID: vid,
                    statement: "Based on your history, your last dyno predates your current hardware.",
                    evidence: "\(part.name) went on \(short(hwDate)), \(days) days after your latest pull (\(short(dyno))) — the recorded figure may not reflect the car now.",
                    confidence: .strong, tone: .caution, provenance: .derived))
            }
        }

        // 3d. Plateau — parts added between the last two pulls but the dyno barely moved.
        let dynos = vehicle.performanceRecords
            .filter { $0.type == .dyno && $0.wheelHorsepower != nil }
            .sorted { $0.date > $1.date }
        if dynos.count >= 2,
           let latest = dynos.first?.wheelHorsepower, let latestDate = dynos.first?.date,
           let prior = dynos.dropFirst().first?.wheelHorsepower, let priorDate = dynos.dropFirst().first?.date {
            let changed = vehicle.installedParts(after: priorDate, upTo: latestDate)
            let gain = latest - prior
            if !changed.isEmpty && gain <= max(3, prior * 0.02) {
                out.append(StewardObservation(
                    ruleID: "dyno.plateau", subjectID: vid,
                    statement: "Based on your history, recent changes haven't shown up on the dyno.",
                    evidence: "\(changed.count) part\(changed.count == 1 ? "" : "s") added since your \(short(priorDate)) pull, but the latest reads \(Int(latest)) whp vs \(Int(prior)) — \(gain <= 0 ? "no gain" : "+\(Int(gain)) whp").",
                    confidence: .moderate, tone: .caution, provenance: .derived))
            }
        }

        // 4. Surface when the biography goes quiet — the elapsed time is a confirmed fact.
        if let last = vehicle.lastActivityDate {
            let days = context.days(from: last, to: context.now)
            if days >= 90 {
                out.append(StewardObservation(
                    ruleID: "build.quiet", subjectID: vid,
                    statement: "Based on your history, this build has been quiet for a while.",
                    evidence: "Last logged activity was \(days) days ago (\(short(last))).",
                    confidence: .confirmed, tone: days >= 240 ? .advisory : .informational, provenance: .derived))
            }
        }

        // 4b. Data honesty — undated installed parts weaken every sequence read above.
        let installedParts = vehicle.parts.filter { $0.status == .installed }
        let undated = installedParts.filter { $0.installDate == nil }
        if installedParts.count >= 5, undated.count >= 3,
           Double(undated.count) / Double(installedParts.count) >= 0.4 {
            out.append(StewardObservation(
                ruleID: "data.undatedParts", subjectID: vid,
                statement: "Based on your history, dating a few more parts would sharpen what I can tell you.",
                evidence: "\(undated.count) of \(installedParts.count) installed parts have no install date — the timeline, and my read on sequence, only see dated ones.",
                confidence: .confirmed, tone: .informational, provenance: .derived))
        }

        // 5. Cost-to-power — an approximation, and labeled as one. Comparing a measured wheel
        //    figure against a factory *crank* rating is not dyno-corrected truth.
        if let costPerHp = vehicle.costPerHorsepowerGained,
           let gained = vehicle.horsepowerGainedOverStock,
           let baseline = vehicle.estimatedStockWheelHP {
            let lossNote = vehicle.stockWheelBaselineIsAssumed
                ? "assuming ~\(Int(Drivetrain.unknown.typicalLossFraction * 100))% driveline loss"
                : "~\(Int(vehicle.drivetrain.typicalLossFraction * 100))% \(vehicle.drivetrain.label) driveline loss"
            out.append(StewardObservation(
                ruleID: "efficiency.costPerHp", subjectID: vid,
                statement: "I observed your approximate cost-to-power efficiency.",
                evidence: "~\(dollars(costPerHp)) per wheel-hp gained (~\(Int(gained)) whp over an estimated \(Int(baseline)) whp stock baseline, \(dollars(vehicle.totalInvested)) invested). Wheel-to-wheel estimate, \(lossNote); not dyno-corrected.",
                confidence: .moderate, tone: .informational, provenance: .derived))
        }

        return out.sorted(by: ordered)
    }

    /// Builds a support-gap observation honestly from what we *know* about the subsystem.
    static func supportGap(_ vehicle: Vehicle, support: PartCategory,
                           subsystem: String, trigger: String) -> StewardObservation? {
        let ruleID = "gap.\(support.rawValue)"
        switch vehicle.knowledge(of: support) {
        case .confirmedPresent, .unknown:
            return nil
        case .confirmedAbsent:
            return StewardObservation(
                ruleID: ruleID, subjectID: vehicle.id,
                statement: "No upgraded \(subsystem) is recorded, and the factory system is confirmed in place.",
                evidence: "\(trigger) The factory \(subsystem) was marked as retained — worth weighing against the added load.",
                confidence: .strong, tone: .caution, provenance: .recorded)
        case .undocumented:
            let strong = vehicle.isWellDocumented
            return StewardObservation(
                ruleID: ruleID, subjectID: vehicle.id,
                statement: "\(capitalizedFirst(subsystem)) support hasn't been documented.",
                evidence: "\(trigger) No \(subsystem) parts are logged — this may be a real gap, or just an incomplete record.",
                confidence: strong ? .moderate : .weak,
                tone: strong ? .caution : .informational, provenance: .derived)
        }
    }

    // MARK: - Live observations

    /// Reasoning over a live telemetry frame, against the vehicle's own `OperatingEnvelope`.
    /// Each rule reads only the *fresh* measurement for its metric — stale or missing produces
    /// nothing. Boost is judged only when it's a meaningful signal for this car (forced
    /// induction) and only under throttle, so an off-throttle spike or an NA car never trips
    /// it. A value decoded from the adapter this instant is `.measuredLive` and grades higher.
    public static func observe(frame: LiveTelemetryFrame, for vehicle: Vehicle,
                               context: StewardContext = .live) -> [StewardObservation] {
        var out: [StewardObservation] = []
        let vid = vehicle.id
        let env = vehicle.operatingEnvelope
        let now = context.now

        if let coolant = frame.fresh(\.coolantTempF, now: now) {
            let measured = coolant.source == .obdAdapter
            let word = measured ? "Measured" : "Estimated"
            let prov: StewardObservation.Provenance = measured ? .measuredLive : .estimatedLive
            if coolant.value >= env.coolantCriticalF {
                out.append(StewardObservation(
                    ruleID: "live.coolantCritical", subjectID: vid,
                    statement: "The data suggests coolant is running hot.",
                    evidence: "\(word) coolant \(Int(coolant.value))°F, at/above this car's \(Int(env.coolantCriticalF))°F limit.",
                    confidence: measured ? .strong : .weak, tone: .advisory, provenance: prov))
            } else if coolant.value >= env.coolantCautionF {
                out.append(StewardObservation(
                    ruleID: "live.coolantCaution", subjectID: vid,
                    statement: "I observed coolant climbing toward the upper range.",
                    evidence: "\(word) coolant \(Int(coolant.value))°F (caution from \(Int(env.coolantCautionF))°F).",
                    confidence: measured ? .moderate : .weak, tone: .caution, provenance: prov))
            }
        }

        // Boost only where it means something: a boost envelope exists (forced induction) and
        // the throttle is actually open. Off-throttle or NA → no claim.
        if let boostCaution = env.boostCautionPsi,
           let boost = frame.fresh(\.boostPsi, now: now), boost.value >= boostCaution,
           let throttle = frame.fresh(\.throttlePercent, now: now), throttle.value >= 50 {
            let measured = boost.source == .obdAdapter
            let word = measured ? "Measured" : "Estimated"
            out.append(StewardObservation(
                ruleID: "live.boost", subjectID: vid,
                statement: "I observed boost near the top of this car's expected range.",
                evidence: "\(word) \(String(format: "%.1f", boost.value)) psi at \(Int(throttle.value))% throttle (caution from \(String(format: "%.0f", boostCaution)) psi).",
                confidence: measured ? .moderate : .weak, tone: .informational,
                provenance: measured ? .measuredLive : .estimatedLive))
        }

        return out
    }

    // MARK: - Ordering + formatting

    /// Deterministic total order: severity, then evidence band, then subject, then rule. No
    /// ties are left to chance, so a briefing never reshuffles between identical rebuilds.
    static func ordered(_ a: StewardObservation, _ b: StewardObservation) -> Bool {
        if rank(a) != rank(b) { return rank(a) > rank(b) }
        if a.subjectID?.uuidString != b.subjectID?.uuidString {
            return (a.subjectID?.uuidString ?? "") < (b.subjectID?.uuidString ?? "")
        }
        return a.ruleID < b.ruleID
    }

    static func rank(_ o: StewardObservation) -> Int {
        let toneWeight: Int
        switch o.tone {
        case .advisory: toneWeight = 200
        case .caution: toneWeight = 100
        case .informational: toneWeight = 0
        }
        return toneWeight + o.confidence.rawValue
    }

    static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    static func dollars(_ value: Double) -> String { value.formatted(.currency(code: "USD")) }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: - Thin interpretation wrappers (retained)

    public static func currentHorsepower(for vehicle: Vehicle) -> Double? { vehicle.currentHorsepowerEstimate }
    public static func horsepowerGained(for vehicle: Vehicle) -> Double? { vehicle.horsepowerGainedOverStock }
    public static func costPerHorsepower(for vehicle: Vehicle) -> Double? { vehicle.costPerHorsepowerGained }
    public static func totalInvested(for vehicle: Vehicle) -> Double { vehicle.totalInvested }
}
