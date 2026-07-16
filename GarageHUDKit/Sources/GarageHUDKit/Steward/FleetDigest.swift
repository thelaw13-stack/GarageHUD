import Foundation

/// GarageHUD's temporal memory. Until now the Steward reasoned only about the *present* — open a
/// car, learn its state, close it, forget you ever looked. A `FleetSnapshot` records the salient
/// state of every car at a moment in time; comparing the last snapshot against the fleet now yields
/// a **"Since you were last here"** digest. That turns the app from something you *query* into
/// something that *watches*. Pure and testable — persistence and UI wrap around it.

/// One car's salient state at a point in time. Deliberately small: just enough to detect the
/// changes worth surfacing, not a full copy of the record.
public struct VehicleSnapshot: Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var inService: Bool
    public var maintenanceDueRank: Int   // 0 ok · 1 due-soon · 2 overdue
    public var mileage: Int?
    public var dynoWHP: Int?
    public var pullCount: Int
    public var installedParts: Int
    public var attentionCount: Int

    public init(id: UUID, name: String, inService: Bool, maintenanceDueRank: Int, mileage: Int?,
                dynoWHP: Int?, pullCount: Int, installedParts: Int, attentionCount: Int) {
        self.id = id; self.name = name; self.inService = inService
        self.maintenanceDueRank = maintenanceDueRank; self.mileage = mileage; self.dynoWHP = dynoWHP
        self.pullCount = pullCount; self.installedParts = installedParts; self.attentionCount = attentionCount
    }
}

public struct FleetSnapshot: Codable, Equatable, Sendable {
    public var takenAt: Date
    public var vehicles: [VehicleSnapshot]
    public init(takenAt: Date, vehicles: [VehicleSnapshot]) { self.takenAt = takenAt; self.vehicles = vehicles }
}

/// One thing that changed since the last visit, in the Steward's voice.
public struct FleetChange: Identifiable, Equatable, Sendable {
    public enum Kind: String, Sendable {
        case addedVehicle, removedVehicle, wentIntoService, backInService, serviceWorsened, serviceCleared
        case dyno, pull, mileage, addedParts
    }
    public let id: String
    public let vehicleID: UUID?
    public let text: String
    public let tone: StewardObservation.Tone
    public let kind: Kind
}

public struct FleetDigest: Equatable, Sendable {
    public let since: Date
    public let changes: [FleetChange]
    public var headline: String {
        let n = changes.count
        return "Since you were last here — \(n) update\(n == 1 ? "" : "s")."
    }
}

public enum FleetDigestBuilder {
    /// Odometer must move at least this much to be worth mentioning (ignore GPS/logging jitter).
    public static let mileageThreshold = 10

    public static func snapshot(of vehicles: [Vehicle], at date: Date = .now,
                                context: StewardContext = .live) -> FleetSnapshot {
        FleetSnapshot(takenAt: date, vehicles: vehicles.map { v in
            VehicleSnapshot(
                id: v.id, name: v.displayName, inService: v.serviceStatus.isInService,
                maintenanceDueRank: dueRank(v.maintenanceDue(now: date, calendar: context.calendar)),
                mileage: v.currentMileage,
                dynoWHP: v.performanceRecords.filter { $0.type == .dyno && $0.wheelHorsepower != nil }
                    .sorted { $0.date > $1.date }.first?.wheelHorsepower.map { Int($0) },
                pullCount: v.pullReports.count,
                installedParts: v.installedPartsCount,
                attentionCount: Steward.observe(v, context: context).filter { $0.tone != .informational }.count)
        })
    }

    /// The digest of everything that changed between a prior snapshot and the fleet now. Nil when
    /// there's no prior snapshot (first launch) or nothing meaningful changed.
    public static func digest(from previous: FleetSnapshot?, to vehicles: [Vehicle],
                              now: Date = .now, context: StewardContext = .live) -> FleetDigest? {
        guard let previous else { return nil }
        let current = snapshot(of: vehicles, at: now, context: context)
        let byID = Dictionary(uniqueKeysWithValues: previous.vehicles.map { ($0.id, $0) })
        let currentIDs = Set(current.vehicles.map(\.id))
        var changes: [FleetChange] = []

        for c in current.vehicles {
            guard let p = byID[c.id] else {
                changes.append(change(.addedVehicle, c.id, "\(c.name) joined the garage.", .informational)); continue
            }
            // Service condition — worsening is a caution, clearing is good news.
            if !p.inService && c.inService {
                changes.append(change(.wentIntoService, c.id, "\(c.name) went into the service bay.", .informational))
            } else if p.inService && !c.inService {
                changes.append(change(.backInService, c.id, "\(c.name) is back in service.", .informational))
            }
            if c.maintenanceDueRank > p.maintenanceDueRank {
                let word = c.maintenanceDueRank == 2 ? "overdue" : "due soon"
                changes.append(change(.serviceWorsened, c.id, "\(c.name)'s service is now \(word).",
                                      c.maintenanceDueRank == 2 ? .advisory : .caution))
            } else if c.maintenanceDueRank < p.maintenanceDueRank && c.maintenanceDueRank == 0 {
                changes.append(change(.serviceCleared, c.id, "\(c.name)'s service is current again.", .informational))
            }
            // New evidence logged.
            if let hp = c.dynoWHP, c.dynoWHP != p.dynoWHP {
                changes.append(change(.dyno, c.id, "\(c.name) logged a dyno — \(hp) whp.", .informational))
            }
            if c.pullCount > p.pullCount {
                let n = c.pullCount - p.pullCount
                changes.append(change(.pull, c.id, "\(c.name) captured \(n) pull\(n == 1 ? "" : "s").", .informational))
            }
            if let cm = c.mileage, let pm = p.mileage, cm - pm >= mileageThreshold {
                changes.append(change(.mileage, c.id, "\(c.name) +\((cm - pm).formatted(.number.grouping(.automatic))) mi.", .informational))
            }
            if c.installedParts > p.installedParts {
                let n = c.installedParts - p.installedParts
                changes.append(change(.addedParts, c.id, "\(c.name) gained \(n) installed part\(n == 1 ? "" : "s").", .informational))
            }
        }
        for p in previous.vehicles where !currentIDs.contains(p.id) {
            changes.append(change(.removedVehicle, p.id, "\(p.name) left the garage.", .informational))
        }

        guard !changes.isEmpty else { return nil }
        // Most-serious first, then stable by text so the same inputs render identically.
        let ordered = changes.sorted { a, b in
            if toneRank(a.tone) != toneRank(b.tone) { return toneRank(a.tone) > toneRank(b.tone) }
            return a.text < b.text
        }
        return FleetDigest(since: previous.takenAt, changes: ordered)
    }

    // MARK: Helpers

    private static func change(_ kind: FleetChange.Kind, _ vid: UUID, _ text: String,
                               _ tone: StewardObservation.Tone) -> FleetChange {
        FleetChange(id: "\(kind.rawValue).\(vid.uuidString)", vehicleID: vid, text: text, tone: tone, kind: kind)
    }
    private static func dueRank(_ d: MaintenanceItem.Due) -> Int {
        switch d { case .ok: return 0; case .dueSoon: return 1; case .overdue: return 2 }
    }
    private static func toneRank(_ t: StewardObservation.Tone) -> Int {
        switch t { case .advisory: return 2; case .caution: return 1; case .informational: return 0 }
    }
}
