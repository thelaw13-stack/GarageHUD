import Foundation

/// Fleet Steward — the reasoning layer. GarageHUD owns memory; Steward interprets it.
///
/// Steward never owns truth and never manufactures urgency. It reads recorded data,
/// emits `StewardObservation`s that carry their own evidence and a confidence level,
/// and orders them so the most decision-relevant surfaces first. Language is
/// evidence-first ("I observed… / The data suggests… / Based on your history…").
public enum Steward {

    // MARK: - Garage observations (reasoned over recorded memory)

    /// The current watch-set. Five rules chosen for a strong signal-to-noise ratio:
    /// two are near-certain derived facts (efficiency, freshness); three are
    /// well-understood build-integrity gaps whose confidence is stated honestly.
    public static func observe(_ vehicle: Vehicle) -> [StewardObservation] {
        var out: [StewardObservation] = []
        let installed = Set(vehicle.parts.filter { $0.status == .installed }.map(\.category))
        let hasForcedInduction = installed.contains(.forcedInduction)

        // 1. Fueling must keep up with forced induction.
        if hasForcedInduction && !installed.contains(.fueling) {
            out.append(StewardObservation(
                statement: "The data suggests fueling may not keep up with your forced-induction setup.",
                evidence: "Forced induction is installed, but no fuel-system parts (pump, injectors, rail) are logged.",
                confidence: 88, tone: .caution, provenance: .recorded))
        }

        // 2. Added airflow makes heat, and heat is where reliability goes to die.
        if hasForcedInduction && !installed.contains(.cooling) {
            out.append(StewardObservation(
                statement: "The data suggests heat management could be a gap.",
                evidence: "Forced induction is installed; no cooling parts (radiator, oil cooler, intercooler) are logged.",
                confidence: 76, tone: .caution, provenance: .recorded))
        }

        // 3. Braking should keep pace with power and grip.
        let powerUp = (vehicle.horsepowerGainedOverStock ?? 0) >= 40
        if (installed.contains(.suspension) || powerUp) && !installed.contains(.brakes) {
            out.append(StewardObservation(
                statement: "The data suggests braking hasn't kept pace with the rest of the build.",
                evidence: installed.contains(.suspension)
                    ? "Suspension is upgraded, but no brake parts are logged."
                    : "Power is up meaningfully over stock, but no brake parts are logged.",
                confidence: 70, tone: .caution, provenance: .recorded))
        }

        // 3b. Sequence hazard — reads the *timeline*, not just the present set. If boost
        //     went on before the fueling caught up, that's a window worth naming even if
        //     fueling is on the car now. Only fires when both installs are actually dated.
        if hasForcedInduction,
           let fiDate = vehicle.earliestInstall(in: .forcedInduction),
           let fuelDate = vehicle.earliestInstall(in: .fueling),
           fiDate < fuelDate {
            let days = Calendar.current.dateComponents([.day], from: fiDate, to: fuelDate).day ?? 0
            if days >= 14 {
                out.append(StewardObservation(
                    statement: "Based on your history, forced induction ran ahead of the fueling for a stretch.",
                    evidence: "Boost was installed \(Self.short(fiDate)); fueling support followed \(days) days later (\(Self.short(fuelDate))).",
                    confidence: 72, tone: .caution, provenance: .derived))
            }
        }

        // 4. Stewardship thinks in decades — surface when the biography goes quiet.
        if let last = vehicle.lastActivityDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: .now).day ?? 0
            if days >= 90 {
                out.append(StewardObservation(
                    statement: "Based on your history, this build has been quiet for a while.",
                    evidence: "Last logged activity was \(days) days ago (\(Self.short(last))).",
                    confidence: 95, tone: days >= 240 ? .advisory : .informational, provenance: .derived))
            }
        }

        // 5. A near-certain derived fact: what each gained horsepower has cost.
        if let costPerHp = vehicle.costPerHorsepowerGained,
           let gained = vehicle.horsepowerGainedOverStock {
            out.append(StewardObservation(
                statement: "I observed your cost-to-power efficiency.",
                evidence: "\(Self.dollars(costPerHp)) per wheel-hp gained "
                    + "(\(Int(gained)) whp over stock, \(Self.dollars(vehicle.totalInvested)) invested).",
                confidence: 97, tone: .informational, provenance: .derived))
        }

        return out.sorted { rank($0) > rank($1) }
    }

    // MARK: - Live observations (estimated telemetry hook)

    /// Reasoning over a live telemetry frame. Today the data source is *estimated*
    /// (no OBD-II hardware yet), so these observations are deliberately low-confidence
    /// and tagged `.estimatedLive`. When a real Bluetooth ELM327 source replaces the
    /// simulator, only the provenance/confidence need to rise — the rules stay.
    public static func observe(live metrics: LiveMetrics, for vehicle: Vehicle) -> [StewardObservation] {
        var out: [StewardObservation] = []

        if metrics.coolantTempF >= 235 {
            out.append(StewardObservation(
                statement: "The data suggests coolant is running hot.",
                evidence: "Estimated coolant \(Int(metrics.coolantTempF))°F under load.",
                confidence: 66, tone: .advisory, provenance: .estimatedLive))
        } else if metrics.coolantTempF >= 215 {
            out.append(StewardObservation(
                statement: "I observed coolant climbing toward the upper range.",
                evidence: "Estimated coolant \(Int(metrics.coolantTempF))°F.",
                confidence: 60, tone: .caution, provenance: .estimatedLive))
        }

        if metrics.boostPsi >= 18 {
            out.append(StewardObservation(
                statement: "I observed boost near the top of a typical street range.",
                evidence: "Estimated \(String(format: "%.1f", metrics.boostPsi)) psi.",
                confidence: 58, tone: .informational, provenance: .estimatedLive))
        }

        return out
    }

    // MARK: - Ordering + formatting

    private static func rank(_ o: StewardObservation) -> Int {
        let toneWeight: Int
        switch o.tone {
        case .advisory: toneWeight = 200
        case .caution: toneWeight = 100
        case .informational: toneWeight = 0
        }
        return toneWeight + o.confidence
    }

    private static func short(_ date: Date) -> String {
        let f = DateFormatter(); f.dateStyle = .medium; return f.string(from: date)
    }
    private static func dollars(_ value: Double) -> String {
        value.formatted(.currency(code: "USD"))
    }

    // MARK: - Thin interpretation wrappers (retained)

    public static func currentHorsepower(for vehicle: Vehicle) -> Double? { vehicle.currentHorsepowerEstimate }
    public static func horsepowerGained(for vehicle: Vehicle) -> Double? { vehicle.horsepowerGainedOverStock }
    public static func costPerHorsepower(for vehicle: Vehicle) -> Double? { vehicle.costPerHorsepowerGained }
    public static func totalInvested(for vehicle: Vehicle) -> Double { vehicle.totalInvested }
}
