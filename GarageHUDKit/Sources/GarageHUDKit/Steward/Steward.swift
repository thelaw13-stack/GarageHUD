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

        // 3. Braking should keep pace with power and grip. The power leg keys on the owner's
        //    driveline-attention level (W-044), not a flat gain — stage-1 bumps stay quiet.
        let powerUp = vehicle.powerDemandsDrivelineAttention
        if vehicle.knowledge(of: .suspension) == .confirmedPresent || powerUp {
            let trigger = vehicle.knowledge(of: .suspension) == .confirmedPresent
                ? "Suspension is upgraded." : "Power is past \(Int(Vehicle.drivelineAttentionWheelHP)) whp."
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
                    ruleID: StewardRuleID.sequenceFIAheadOfFueling, subjectID: vid,
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
                    ruleID: StewardRuleID.tuneStale, subjectID: vid,
                    statement: "Based on your history, your last dyno predates your current hardware.",
                    evidence: "\(part.name) went on \(short(hwDate)), \(days) days after your latest pull (\(short(dyno))) — the recorded figure may not reflect the car now.",
                    confidence: .strong, tone: .caution, provenance: .derived))
            }
        }

        // 3d. Plateau — parts added between the last two pulls but the dyno barely moved.
        let dynos = vehicle.measuredDynoRecords
        if dynos.count >= 2,
           let latest = dynos.first?.wheelHorsepower, let latestDate = dynos.first?.date,
           let prior = dynos.dropFirst().first?.wheelHorsepower, let priorDate = dynos.dropFirst().first?.date {
            let changed = vehicle.installedParts(after: priorDate, upTo: latestDate)
            let gain = latest - prior
            if !changed.isEmpty && gain <= max(3, prior * 0.02) {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.dynoPlateau, subjectID: vid,
                    statement: "Based on your history, recent changes haven't shown up on the dyno.",
                    evidence: "\(changed.count) part\(changed.count == 1 ? "" : "s") added since your \(short(priorDate)) pull, but the latest reads \(Int(latest)) whp vs \(Int(prior)) — \(gain <= 0 ? "no gain" : "+\(Int(gain)) whp").",
                    confidence: .moderate, tone: .caution, provenance: .derived))
            }
        }

        // 3e. Out of service — a car that's apart on purpose. State it plainly, and it also
        //     suppresses the "quiet build" scolding below (a teardown isn't neglect).
        if vehicle.serviceStatus.isInService {
            let sinceNote = vehicle.serviceStatus.since.map { " since \(short($0))" } ?? ""
            let reason = vehicle.serviceStatus.reason.isEmpty ? "Out of service." : vehicle.serviceStatus.reason
            let progress = vehicle.serviceStatus.progressText.map { " Rebuild checklist: \($0)." } ?? ""
            let flaggedCount = vehicle.partsFlaggedForRebuild.count
            let flagged = flaggedCount > 0 ? " \(flaggedCount) part\(flaggedCount == 1 ? "" : "s") flagged for replacement." : ""
            out.append(StewardObservation(
                ruleID: StewardRuleID.serviceInService, subjectID: vid,
                statement: "This car is currently out of service.",
                evidence: "\(reason)\(sinceNote).\(progress)\(flagged)",
                confidence: .confirmed, tone: .informational, provenance: .recorded))
        }

        // 3f. Upkeep — overdue or soon-due scheduled maintenance. A confirmed fact, judged the
        //     same way every other surface judges it: whichever of the time interval and the
        //     mileage interval arrives first. (This rule once used the time-only overload, so a
        //     truck 3,000 mi over its oil interval produced no observation while the briefing
        //     header called it overdue — two surfaces contradicting each other.)
        let odo = vehicle.currentMileage
        for item in vehicle.maintenance {
            let milesRemaining = item.milesUntilDue(currentMileage: odo)
            switch item.due(now: context.now, calendar: context.calendar, currentMileage: odo) {
            case .overdue:
                let evidence: String
                if let m = milesRemaining, m <= 0, let target = item.dueMileage, let odo {
                    evidence = "Odometer \(odo.formatted(.number.grouping(.automatic))) mi is \((-m).formatted(.number.grouping(.automatic))) mi past the \(target.formatted(.number.grouping(.automatic))) mi mark."
                } else {
                    evidence = "Due \(short(item.dueDate(context.calendar))); last done \(short(item.lastServiced)) on a \(item.intervalMonths)-month interval."
                }
                out.append(StewardObservation(
                    ruleID: StewardRuleID.maintenanceOverdue(item.id), subjectID: vid,
                    statement: "\(item.name) is overdue.",
                    evidence: evidence,
                    confidence: .confirmed, tone: .advisory, provenance: .derived))
            case .dueSoon:
                let evidence: String
                if let m = milesRemaining, m > 0, m <= 500 {
                    evidence = "Due in \(m.formatted(.number.grouping(.automatic))) mi."
                } else {
                    evidence = "Due \(short(item.dueDate(context.calendar)))."
                }
                out.append(StewardObservation(
                    ruleID: StewardRuleID.maintenanceDueSoon(item.id), subjectID: vid,
                    statement: "\(item.name) is due soon.",
                    evidence: evidence,
                    confidence: .confirmed, tone: .caution, provenance: .derived))
            case .ok:
                break
            }
        }

        // 3g. Pull Guardian — a recently captured pull went over the boost ceiling or ran heavily
        //     over target. Only recent pulls stay actionable; the confidence carries forward from
        //     the run itself, so a mostly-simulated capture never reads as more certain than it was.
        if let flagged = vehicle.pullReports
            .filter({ $0.boostBreachedCeiling || ($0.overTargetFraction ?? 0) >= 0.5 })
            .max(by: { $0.endedAt < $1.endedAt }),
           context.days(from: flagged.endedAt, to: context.now) <= 14 {
            out.append(StewardObservation(
                ruleID: StewardRuleID.pullFlagged(flagged.id), subjectID: vid,
                statement: flagged.verdictStatement,
                evidence: "\(flagged.verdictEvidence) Captured \(short(flagged.endedAt)) (\(flagged.feedLabel)).",
                confidence: flagged.confidence, tone: .caution, provenance: .recorded))
        }

        // 4. Note when the record — not necessarily the car — has gone quiet. Never for a car that's
        //    deliberately in service. `lastActivityDate` is nil until something is logged, so a
        //    freshly-added car is never called "neglected". Stays informational: not logging isn't
        //    neglect, so Steward observes it plainly rather than scolding.
        if !vehicle.serviceStatus.isInService, let last = vehicle.lastActivityDate {
            let days = context.days(from: last, to: context.now)
            if days >= 180 {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.buildQuiet, subjectID: vid,
                    statement: "The log for this car has been quiet for a while.",
                    evidence: "Nothing new has been recorded in \(days) days (last was \(short(last))) — not necessarily inactivity, just an aging record.",
                    confidence: .confirmed, tone: .informational, provenance: .derived))
            }
        }

        // 4b. Data honesty — undated installed parts weaken every sequence read above.
        let installedParts = vehicle.parts.filter { $0.status == .installed }
        let undated = installedParts.filter { $0.installDate == nil }
        if installedParts.count >= 5, undated.count >= 3,
           Double(undated.count) / Double(installedParts.count) >= 0.4 {
            out.append(StewardObservation(
                ruleID: StewardRuleID.dataUndatedParts, subjectID: vid,
                statement: "Based on your history, dating a few more parts would sharpen what I can tell you.",
                evidence: "\(undated.count) of \(installedParts.count) installed parts have no install date — the timeline, and my read on sequence, only see dated ones.",
                confidence: .confirmed, tone: .informational, provenance: .derived))
        }

        // 4c. Data honesty — the odometer record disagrees with itself. A later-dated event
        //     with a LOWER reading poisons current mileage, the learned driving rate, and every
        //     mileage projection; surface the contradiction rather than silently reasoning on it.
        let odoReadings = vehicle.buildEvents
            .compactMap { e in e.mileage.map { (date: e.date, miles: $0) } }
            .sorted { $0.date < $1.date }
        if let pair = zip(odoReadings, odoReadings.dropFirst()).first(where: { $1.miles < $0.miles }) {
            out.append(StewardObservation(
                ruleID: StewardRuleID.dataOdometerRegression, subjectID: vid,
                statement: "The odometer record disagrees with itself.",
                evidence: "\(short(pair.1.date)) logs \(pair.1.miles.formatted(.number.grouping(.automatic))) mi — lower than the \(pair.0.miles.formatted(.number.grouping(.automatic))) mi recorded \(short(pair.0.date)). One of them is off, and mileage projections lean on these.",
                confidence: .confirmed, tone: .caution, provenance: .derived))
        }

        // 5. Cost-to-power — an approximation, and labeled as one. Comparing a measured wheel
        //    figure against a factory *crank* rating is not dyno-corrected truth.
        // Only meaningful once real power has been added — a $/hp figure over a handful of wheel-hp
        // is volatile noise (and pointless on a utility/OEM build), so require a genuine gain.
        if let costPerHp = vehicle.costPerHorsepowerGained,
           let gained = vehicle.horsepowerGainedOverStock, gained >= 25,
           let baseline = vehicle.estimatedStockWheelHP {
            let lossNote = vehicle.stockWheelBaselineIsAssumed
                ? "assuming ~\(Int(Drivetrain.unknown.typicalLossFraction * 100))% driveline loss"
                : "~\(Int(vehicle.drivetrain.typicalLossFraction * 100))% \(vehicle.drivetrain.label) driveline loss"
            out.append(StewardObservation(
                ruleID: StewardRuleID.efficiencyCostPerHp, subjectID: vid,
                statement: "This build runs about \(dollars(costPerHp)) per wheel-hp gained.",
                evidence: "~\(Int(gained)) whp over an estimated \(Int(baseline)) whp stock baseline, \(dollars(vehicle.totalInvested)) invested. Wheel-to-wheel estimate, \(lossNote); not dyno-corrected.",
                confidence: .moderate, tone: .informational, provenance: .derived))
        }

        return out.sorted(by: ordered)
    }

    /// Builds a support-gap observation honestly from what we *know* about the subsystem.
    static func supportGap(_ vehicle: Vehicle, support: PartCategory,
                           subsystem: String, trigger: String) -> StewardObservation? {
        let ruleID = StewardRuleID.gap(support)
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
            // A wishlist part in this category is on the record — the evidence must acknowledge
            // it (saying "no parts are logged" would deny a logged part), while the gap itself
            // stays open: planned is intent, not coverage.
            if vehicle.hasPlanned(in: support) {
                return StewardObservation(
                    ruleID: ruleID, subjectID: vehicle.id,
                    statement: "\(capitalizedFirst(subsystem)) support is planned but not yet installed.",
                    evidence: "\(trigger) A \(subsystem) part is on the wishlist — the gap stays open until it's on the car.",
                    confidence: strong ? .moderate : .weak,
                    tone: strong ? .caution : .informational, provenance: .derived)
            }
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
                    ruleID: StewardRuleID.liveCoolantCritical, subjectID: vid,
                    statement: "The data suggests coolant is running hot.",
                    evidence: "\(word) coolant \(Int(coolant.value))°F, at/above this car's \(Int(env.coolantCriticalF))°F limit.",
                    confidence: measured ? .strong : .weak, tone: .advisory, provenance: prov))
            } else if coolant.value >= env.coolantCautionF {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.liveCoolantCaution, subjectID: vid,
                    statement: "I observed coolant climbing toward the upper range.",
                    evidence: "\(word) coolant \(Int(coolant.value))°F (caution from \(Int(env.coolantCautionF))°F).",
                    confidence: measured ? .moderate : .weak, tone: .caution, provenance: prov))
            }
        }

        // Boost rules require an open throttle; off-throttle or NA → no claim.
        let boostFresh = frame.fresh(\.boostPsi, now: now)
        let throttleFresh = frame.fresh(\.throttlePercent, now: now)
        if let boost = boostFresh, let throttle = throttleFresh, throttle.value >= 50 {
            let measured = boost.source == .obdAdapter
            let word = measured ? "Measured" : "Estimated"
            let prov: StewardObservation.Provenance = measured ? .measuredLive : .estimatedLive
            let psi = String(format: "%.1f", boost.value)

            // 1. A hard ceiling the owner set — over-boost is the most serious live boost event.
            if let ceiling = env.maxSustainedBoostPsi, boost.value > ceiling {
                out.append(StewardObservation(
                    ruleID: StewardRuleID.liveBoostCeiling, subjectID: vid,
                    statement: "The data suggests boost is above your set ceiling.",
                    evidence: "\(word) \(psi) psi at \(Int(throttle.value))% throttle, over your \(String(format: "%.1f", ceiling)) psi ceiling.",
                    confidence: measured ? .strong : .weak, tone: .advisory, provenance: prov))
            }

            // 2. RPM-banded tune targets, if the owner defined a profile — supersede the generic
            //    caution because they describe what *this tune* should make at this RPM.
            if let rpm = frame.fresh(\.rpm, now: now),
               let band = env.expectedBoostByRPM.first(where: { $0.contains(rpm: rpm.value) }) {
                if boost.value > band.expectedHighPsi {
                    out.append(StewardObservation(
                        ruleID: StewardRuleID.liveBoostOverTarget, subjectID: vid,
                        statement: "I observed boost above target for this RPM.",
                        evidence: "\(word) \(psi) psi at \(Int(rpm.value)) rpm; tune target tops out at \(String(format: "%.1f", band.expectedHighPsi)) psi here.",
                        confidence: measured ? .moderate : .weak, tone: .caution, provenance: prov))
                } else if boost.value < band.expectedLowPsi {
                    out.append(StewardObservation(
                        ruleID: StewardRuleID.liveBoostUnderTarget, subjectID: vid,
                        statement: "I observed boost below target for this RPM.",
                        evidence: "\(word) \(psi) psi at \(Int(rpm.value)) rpm; tune target starts at \(String(format: "%.1f", band.expectedLowPsi)) psi here — could be a leak, wastegate, or just spool.",
                        confidence: measured ? .moderate : .weak, tone: .informational, provenance: prov))
                }
            } else if let boostCaution = env.boostCautionPsi, boost.value >= boostCaution {
                // 3. No tune profile: the single generic caution.
                out.append(StewardObservation(
                    ruleID: StewardRuleID.liveBoost, subjectID: vid,
                    statement: "I observed boost near the top of this car's expected range.",
                    evidence: "\(word) \(psi) psi at \(Int(throttle.value))% throttle (caution from \(String(format: "%.0f", boostCaution)) psi).",
                    confidence: measured ? .moderate : .weak, tone: .informational, provenance: prov))
            }
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
