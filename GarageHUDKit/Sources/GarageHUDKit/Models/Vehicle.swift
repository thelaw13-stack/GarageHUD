import Foundation

public struct Vehicle: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var make: String
    public var model: String
    public var year: Int
    public var trim: String = ""
    public var nickname: String = ""
    public var colorName: String = ""
    public var garageSlot: Int
    public var dateAdded: Date = .now
    public var coverImageFilename: String?

    public var engineDescription: String = ""
    public var drivetrainDescription: String = ""
    public var factoryHorsepower: Double?
    public var factoryTorque: Double?
    public var factoryWeightLbs: Double?
    /// The measurement basis of `factoryHorsepower`. Defaults to `.factoryCrank`, which is
    /// what a manufacturer rating almost always is — and why comparing it to a wheel-dyno
    /// number is only ever an approximation.
    public var factoryPowerBasis: PowerBasis = .factoryCrank
    /// Drivetrain layout, used to normalize a factory crank rating to a wheel-equivalent
    /// baseline when computing power gained. Defaults to `.unknown` (a conservative assumed
    /// loss, flagged as such).
    public var drivetrain: Drivetrain = .unknown
    /// Categories the owner has explicitly confirmed remain factory/stock (no upgrade). This
    /// is the only thing that lets Steward say a system is *confirmed absent* rather than
    /// merely undocumented.
    public var confirmedStockSystems: Set<PartCategory> = []
    /// A per-vehicle override of the live operating limits. When nil, a default envelope is
    /// derived from the record (see `OperatingEnvelope.default(for:)`).
    public var operatingEnvelopeOverride: OperatingEnvelope?
    /// Whether the car is operational or intentionally out of service (teardown/rebuild). A car
    /// that's apart on purpose isn't neglected, and the Steward treats it accordingly.
    public var serviceStatus: ServiceStatus = .operational
    /// A known total-spend figure (e.g. from a build sheet's lump-sum total) that overrides
    /// the sum of itemized part costs when set — most real build sheets give one total, not
    /// per-part pricing, so summing `Part.cost` alone would just read as $0.
    public var documentedTotalInvestment: Double?
    /// What the owner paid to acquire the vehicle — its purchase price. Kept deliberately separate
    /// from `totalInvested` (build/mod spend) and `serviceSpend` (maintenance): three distinct money
    /// facts, never conflated. Nil until recorded.
    public var purchasePrice: Double?
    /// Whether this platform is boosted from the showroom (factory turbo/supercharger). Nil =
    /// infer from the engine description and known model markers; the owner can override either
    /// way in Steward Inputs. See `hasFactoryForcedInduction` (W-045): a factory charger is part
    /// of the car, never a modification — but its boost still matters to live limits, the tuner,
    /// and (once the tune is turned up) support-system reasoning.
    public var factoryForcedInductionOverride: Bool?
    /// Whether this car has an OBD-II port, when the owner has said so explicitly. Nil = infer
    /// (US mandate year, never on an air-cooled classic). The override exists because the
    /// heuristic is a classifier, and classifiers don't get to overrule the owner: a '71 Baja
    /// with an EJ swap and a modern ECU has a port the year rule denies; a gray-market import
    /// may lack one the year rule promises (W-053).
    public var obd2Override: Bool?

    public var parts: [Part] = []
    public var buildEvents: [BuildEvent] = []
    public var performanceRecords: [PerformanceRecord] = []
    public var notes: [Note] = []
    public var photos: [Photo] = []
    public var maintenance: [MaintenanceItem] = []
    /// Wide-open-throttle pulls the Pull Guardian auto-captured from a live session — the run,
    /// graded by how much of its boost claims were actually measured.
    public var pullReports: [PullReport] = []
    /// Where this build is headed — the owner's stated goal, so the Steward can reason about the
    /// *path* (sequence, support, next purchase) and not just the present state. Nil = no plan set.
    public var buildGoal: BuildGoal?
    /// The photo the owner chose to represent this car on the garage grid. When nil (or pointing at
    /// a photo that no longer exists) the hero falls back to the first available photo.
    public var coverPhotoID: UUID? = nil

    public init(
        id: UUID = UUID(),
        make: String,
        model: String,
        year: Int,
        trim: String = "",
        nickname: String = "",
        colorName: String = "",
        garageSlot: Int,
        engineDescription: String = "",
        drivetrainDescription: String = "",
        factoryHorsepower: Double? = nil,
        factoryTorque: Double? = nil,
        factoryWeightLbs: Double? = nil,
        dateAdded: Date = .now
    ) {
        self.id = id
        self.make = make
        self.model = model
        self.year = year
        self.trim = trim
        self.nickname = nickname
        self.colorName = colorName
        self.garageSlot = garageSlot
        self.engineDescription = engineDescription
        self.drivetrainDescription = drivetrainDescription
        self.factoryHorsepower = factoryHorsepower
        self.factoryTorque = factoryTorque
        self.factoryWeightLbs = factoryWeightLbs
        self.dateAdded = dateAdded
    }

    // Tolerant decoding — missing keys fall back to defaults so older garage files and any
    // later-added field decode cleanly (synthesized Decodable does NOT apply property defaults).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        make = try c.decodeIfPresent(String.self, forKey: .make) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        trim = try c.decodeIfPresent(String.self, forKey: .trim) ?? ""
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname) ?? ""
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? ""
        garageSlot = try c.decodeIfPresent(Int.self, forKey: .garageSlot) ?? 1
        dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? .now
        coverImageFilename = try c.decodeIfPresent(String.self, forKey: .coverImageFilename)
        engineDescription = try c.decodeIfPresent(String.self, forKey: .engineDescription) ?? ""
        drivetrainDescription = try c.decodeIfPresent(String.self, forKey: .drivetrainDescription) ?? ""
        factoryHorsepower = try c.decodeIfPresent(Double.self, forKey: .factoryHorsepower)
        factoryTorque = try c.decodeIfPresent(Double.self, forKey: .factoryTorque)
        factoryWeightLbs = try c.decodeIfPresent(Double.self, forKey: .factoryWeightLbs)
        factoryPowerBasis = try c.decodeIfPresent(PowerBasis.self, forKey: .factoryPowerBasis) ?? .factoryCrank
        drivetrain = try c.decodeIfPresent(Drivetrain.self, forKey: .drivetrain) ?? .unknown
        documentedTotalInvestment = try c.decodeIfPresent(Double.self, forKey: .documentedTotalInvestment)
        purchasePrice = try c.decodeIfPresent(Double.self, forKey: .purchasePrice)
        factoryForcedInductionOverride = try c.decodeIfPresent(Bool.self, forKey: .factoryForcedInductionOverride)
        obd2Override = try c.decodeIfPresent(Bool.self, forKey: .obd2Override)
        confirmedStockSystems = try c.decodeIfPresent(Set<PartCategory>.self, forKey: .confirmedStockSystems) ?? []
        operatingEnvelopeOverride = try c.decodeIfPresent(OperatingEnvelope.self, forKey: .operatingEnvelopeOverride)
        serviceStatus = try c.decodeIfPresent(ServiceStatus.self, forKey: .serviceStatus) ?? .operational
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        buildEvents = try c.decodeIfPresent([BuildEvent].self, forKey: .buildEvents) ?? []
        performanceRecords = try c.decodeIfPresent([PerformanceRecord].self, forKey: .performanceRecords) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
        maintenance = try c.decodeIfPresent([MaintenanceItem].self, forKey: .maintenance) ?? []
        pullReports = try c.decodeIfPresent([PullReport].self, forKey: .pullReports) ?? []
        buildGoal = try c.decodeIfPresent(BuildGoal.self, forKey: .buildGoal)
        coverPhotoID = try c.decodeIfPresent(UUID.self, forKey: .coverPhotoID)
    }

    /// Reassign a fresh id to any record that duplicates an earlier one's id, within each collection
    /// (parts, build events, performance records, notes, maintenance). A duplicate id is a real
    /// data hazard — a duplicate `ForEach` id is a hard SwiftUI crash, and it confuses `sheet(item:)`
    /// and sync. Imports/merges can produce them; this heals the data at the source. Returns true if
    /// anything changed. (Photos are left alone — `coverPhotoID` references them.)
    @discardableResult
    public mutating func dedupeRecordIDs() -> Bool {
        var changed = false
        func fix<T>(_ items: inout [T], id: (T) -> UUID, setID: (inout T, UUID) -> Void) {
            var seen = Set<UUID>()
            for i in items.indices {
                if seen.contains(id(items[i])) {
                    setID(&items[i], UUID()); changed = true
                }
                seen.insert(id(items[i]))
            }
        }
        fix(&parts, id: { $0.id }, setID: { $0.id = $1 })
        fix(&buildEvents, id: { $0.id }, setID: { $0.id = $1 })
        fix(&performanceRecords, id: { $0.id }, setID: { $0.id = $1 })
        fix(&notes, id: { $0.id }, setID: { $0.id = $1 })
        fix(&maintenance, id: { $0.id }, setID: { $0.id = $1 })
        fix(&pullReports, id: { $0.id }, setID: { $0.id = $1 })
        fix(&serviceStatus.checklist, id: { $0.id }, setID: { $0.id = $1 })

        // Photos must be unique across the *whole* vehicle — the gallery shows the vehicle's own,
        // its events', and its parts' photos in one ForEach, so a collision anywhere crashes it.
        // Vehicle photos are visited first, so `coverPhotoID` (which points at one) keeps its id.
        var seenPhoto = Set<UUID>()
        func fixPhotos(_ photos: inout [Photo]) {
            for i in photos.indices {
                if seenPhoto.contains(photos[i].id) { photos[i].id = UUID(); changed = true }
                seenPhoto.insert(photos[i].id)
            }
        }
        fixPhotos(&photos)
        for i in buildEvents.indices { fixPhotos(&buildEvents[i].photos) }
        for i in parts.indices { fixPhotos(&parts[i].photos) }
        return changed
    }

    /// Title prefix marking a build event as a completed service, so the service log can be
    /// distinguished from the rest of the biography without a separate event type.
    /// Records an auto-captured pull and logs a compact entry to the biography, so it's part of the
    /// car's memory spine — not a hidden report only the Live tab knows about.
    public mutating func recordPullReport(_ report: PullReport) {
        pullReports.append(report)
        buildEvents.append(BuildEvent(date: report.endedAt, title: "Pull captured: \(report.headline)"))
    }

    public static let servicePrefix = "Serviced: "

    /// Acknowledge a flagged pull as inspected/resolved: dates the report and logs a biography
    /// event, so the resolution is itself a record — not a silent dismissal. The Steward's
    /// flagged-pull observation clears on either a later clean pull OR this acknowledgment.
    @discardableResult
    public mutating func acknowledgePullReport(_ id: UUID, on date: Date = .now) -> Bool {
        guard let i = pullReports.firstIndex(where: { $0.id == id }),
              pullReports[i].acknowledgedAt == nil else { return false }
        pullReports[i].acknowledgedAt = date
        buildEvents.append(BuildEvent(date: date,
                                      title: "Pull flag acknowledged: \(pullReports[i].headline)",
                                      eventDescription: "Owner marked this flagged pull inspected/resolved."))
        return true
    }

    /// True when this item already has a service logged for the given day *at the current odometer*
    /// — so a repeat "mark done" would be an impossible duplicate (you can't service the same thing
    /// twice at the same moment and mileage). The UI uses this to stop the button churning history.
    public func maintenanceAlreadyDone(_ id: UUID, on date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let item = maintenance.first(where: { $0.id == id }) else { return false }
        return serviceLog.contains { e in
            e.title.hasPrefix("\(Vehicle.servicePrefix)\(item.name)")
                && calendar.isDate(e.date, inSameDayAs: date)
                && e.mileage == currentMileage
        }
    }

    /// Record a maintenance item as done: reset its interval and log it to the biography so the
    /// service history is preserved (and shows on the timeline / in the export). No-ops on an
    /// impossible duplicate (already done today at this odometer) so repeated taps can't manufacture
    /// a service history that never happened.
    @discardableResult
    public mutating func markMaintenanceDone(_ id: UUID, on date: Date = .now, cost: Double? = nil) -> Bool {
        guard let i = maintenance.firstIndex(where: { $0.id == id }) else { return false }
        guard !maintenanceAlreadyDone(id, on: date) else { return false }
        let rollback = ServiceRecordLink(
            maintenanceItemID: id,
            previousServicedAt: maintenance[i].lastServiced,
            previousServicedMileage: maintenance[i].lastServicedMileage)
        maintenance[i].lastServiced = date
        // Re-baseline the mileage interval too, so "every 5,000 mi" counts from the current
        // odometer. When the odometer is unknown, the old baseline must be CLEARED, not kept —
        // holding it would claim the service happened at the old mileage and read a fresh oil
        // change as thousands of miles overdue the moment an odometer is finally logged. With no
        // baseline the mileage leg stays dormant (time interval still applies) until the next
        // service records one.
        if maintenance[i].intervalMiles != nil {
            maintenance[i].lastServicedMileage = currentMileage
        }
        let odoNote = currentMileage.map { " @ \($0.formatted(.number.grouping(.automatic))) mi" } ?? ""
        buildEvents.append(BuildEvent(date: date, title: "\(Vehicle.servicePrefix)\(maintenance[i].name)\(odoNote)",
                                      mileage: currentMileage, serviceRecord: rollback, cost: cost))
        return true
    }

    /// Service events for one schedule, newest first. New records carry a durable item id; records
    /// from older GarageHUD builds fall back to the service title so existing history is editable.
    public func serviceRecords(for maintenanceItemID: UUID) -> [BuildEvent] {
        guard let item = maintenance.first(where: { $0.id == maintenanceItemID }) else { return [] }
        return serviceLog.filter { event in
            if let linkedID = event.serviceRecord?.maintenanceItemID {
                return linkedID == maintenanceItemID
            }
            return legacyServiceName(event).caseInsensitiveCompare(item.name) == .orderedSame
        }
    }

    public func latestServiceRecord(for maintenanceItemID: UUID) -> BuildEvent? {
        serviceRecords(for: maintenanceItemID).first
    }

    /// Removes one service history entry and, when it was the current baseline, restores the
    /// schedule to the preceding real service. Returns false for non-service or unknown records.
    @discardableResult
    public mutating func removeServiceRecord(_ eventID: UUID) -> Bool {
        guard let eventIndex = buildEvents.firstIndex(where: { $0.id == eventID }),
              buildEvents[eventIndex].title.hasPrefix(Vehicle.servicePrefix) else { return false }

        let event = buildEvents[eventIndex]
        let itemID = event.serviceRecord?.maintenanceItemID
            ?? maintenance
                .filter { legacyServiceName(event).caseInsensitiveCompare($0.name) == .orderedSame }
                .max { $0.name.count < $1.name.count }?.id
        let itemIndex = itemID.flatMap { id in maintenance.firstIndex { $0.id == id } }

        // If a later linked event depends on this one's baseline, bridge its rollback snapshot
        // across the deleted record so a future undo never resurrects a known-false service.
        if let link = event.serviceRecord,
           let nextIndex = buildEvents.indices
            .filter({
                buildEvents[$0].serviceRecord?.maintenanceItemID == link.maintenanceItemID
                    && buildEvents[$0].date > event.date
            })
            .min(by: { buildEvents[$0].date < buildEvents[$1].date }) {
            buildEvents[nextIndex].serviceRecord?.previousServicedAt = link.previousServicedAt
            buildEvents[nextIndex].serviceRecord?.previousServicedMileage = link.previousServicedMileage
        }

        buildEvents.remove(at: eventIndex)

        guard let itemIndex else { return true }
        let eventWasCurrentBaseline =
            abs(maintenance[itemIndex].lastServiced.timeIntervalSince(event.date)) < 1
        guard eventWasCurrentBaseline else { return true }

        if let prior = serviceRecords(for: maintenance[itemIndex].id).first {
            maintenance[itemIndex].lastServiced = prior.date
            maintenance[itemIndex].lastServicedMileage = prior.mileage
        } else if let rollback = event.serviceRecord {
            maintenance[itemIndex].lastServiced = rollback.previousServicedAt
            maintenance[itemIndex].lastServicedMileage = rollback.previousServicedMileage
        }
        return true
    }

    private func legacyServiceName(_ event: BuildEvent) -> String {
        let title = event.title.replacingOccurrences(of: Vehicle.servicePrefix, with: "")
        return title.components(separatedBy: " @ ").first ?? title
    }

    /// Every photo attached to the car — its own, plus any on build events and parts — as candidates
    /// for the cover. Vehicle photos first, then event photos newest-first, then part photos.
    public var allPhotos: [Photo] {
        photos + buildEvents.sorted { $0.date > $1.date }.flatMap(\.photos) + parts.flatMap(\.photos)
    }

    /// The card/hero photo: the owner's chosen cover if it still exists, else the first vehicle
    /// photo, else the most recent build-event photo — so a car with any photography has a face.
    public var heroPhoto: Photo? {
        if let id = coverPhotoID, let chosen = allPhotos.first(where: { $0.id == id }) { return chosen }
        return photos.first ?? buildEvents.sorted { $0.date > $1.date }.flatMap(\.photos).first
    }

    /// Choose the car's cover photo. Pass nil to clear back to the automatic default.
    public mutating func setCover(_ photoID: UUID?) { coverPhotoID = photoID }

    /// Completed services, newest first — the maintenance record distilled from the biography.
    public var serviceLog: [BuildEvent] {
        buildEvents.filter { $0.title.hasPrefix(Vehicle.servicePrefix) }
            .sorted { $0.date > $1.date }
    }

    /// Total recorded maintenance spend — the sum of costs entered on service records. A distinct
    /// money bucket from `totalInvested` (build/mod parts) and `purchasePrice` (acquisition), so
    /// ownership cost stays honestly separated from what the build cost.
    public var serviceSpend: Double {
        serviceLog.compactMap(\.cost).reduce(0, +)
    }

    /// Set (or clear) the recorded cost on one build event — used to price a service record after
    /// the fact in Service History. Returns false for an unknown id.
    @discardableResult
    public mutating func setBuildEventCost(_ eventID: UUID, _ cost: Double?) -> Bool {
        guard let i = buildEvents.firstIndex(where: { $0.id == eventID }) else { return false }
        buildEvents[i].cost = cost
        return true
    }

    /// The most-pressing maintenance state across all items (worst wins), accounting for both the
    /// time interval and any mileage interval measured against the current odometer.
    public func maintenanceDue(now: Date = .now, calendar: Calendar = .current) -> MaintenanceItem.Due {
        let odo = currentMileage
        let states = maintenance.map { $0.due(now: now, calendar: calendar, currentMileage: odo) }
        if states.contains(.overdue) { return .overdue }
        if states.contains(.dueSoon) { return .dueSoon }
        return .ok
    }

    public var displayName: String {
        nickname.isEmpty ? "\(year) \(make) \(model)" : nickname
    }

    /// Same physical car, by make/model/year — used to fill a bare vehicle from a seed without
    /// relying on ids (which differ between a stale cloud shell and the bundled seed).
    public func identityMatches(_ other: Vehicle) -> Bool {
        make.caseInsensitiveCompare(other.make) == .orderedSame
            && model.caseInsensitiveCompare(other.model) == .orderedSame
            && (year == other.year || other.year == 0)
    }

    /// Return this (bare) vehicle filled with a seed's build — parts, records, events, notes,
    /// service status, and any missing specs — while keeping this vehicle's id and garage slot.
    /// Existing content always wins; only gaps are filled.
    public func filledFromSeed(_ seed: Vehicle) -> Vehicle {
        var v = self
        if v.parts.isEmpty { v.parts = seed.parts }
        if v.performanceRecords.isEmpty { v.performanceRecords = seed.performanceRecords }
        if v.buildEvents.isEmpty { v.buildEvents = seed.buildEvents }
        if v.notes.isEmpty { v.notes = seed.notes }
        if !v.serviceStatus.isInService { v.serviceStatus = seed.serviceStatus }
        v.factoryHorsepower = v.factoryHorsepower ?? seed.factoryHorsepower
        v.factoryTorque = v.factoryTorque ?? seed.factoryTorque
        v.factoryWeightLbs = v.factoryWeightLbs ?? seed.factoryWeightLbs
        if v.documentedTotalInvestment == nil { v.documentedTotalInvestment = seed.documentedTotalInvestment }
        if v.drivetrain == .unknown { v.drivetrain = seed.drivetrain }
        if v.trim.isEmpty { v.trim = seed.trim }
        if v.nickname.isEmpty { v.nickname = seed.nickname }
        if v.engineDescription.isEmpty { v.engineDescription = seed.engineDescription }
        if v.drivetrainDescription.isEmpty { v.drivetrainDescription = seed.drivetrainDescription }
        return v
    }

    public var subtitle: String {
        "\(year) \(make) \(model)\(trim.isEmpty ? "" : " \(trim)")"
    }

    public var installedPartsCount: Int {
        parts.filter { $0.status == .installed }.count
    }

    /// Parts flagged for attention in a rebuild — inspection, replacement, or reorder.
    public var partsFlaggedForRebuild: [Part] {
        parts.filter { $0.flaggedForRebuild && $0.status != .removed }
    }

    public var wishlistPartsCount: Int {
        parts.filter { $0.status == .wishlist }.count
    }

    /// Parts the owner has planned but not yet installed, and their recorded planned spend.
    public var plannedParts: [Part] { parts.filter { $0.status == .wishlist } }
    public var plannedSpend: Double { plannedParts.compactMap(\.cost).reduce(0, +) }
    public func hasPlanned(in category: PartCategory) -> Bool {
        parts.contains { $0.status == .wishlist && $0.category == category }
    }

    public var buildCompletionPercent: Double {
        let total = installedPartsCount + wishlistPartsCount
        guard total > 0 else { return 0 }
        return Double(installedPartsCount) / Double(total) * 100
    }

    /// Money actually spent on the current build — installed parts only. Planned (wishlist) parts
    /// are future spend (`plannedSpend`), and removed parts aren't in the car; neither counts as
    /// invested.
    public var itemizedPartsCost: Double {
        parts.filter { $0.status == .installed }.compactMap(\.cost).reduce(0, +)
    }

    /// The number to show as "total invested" — the **larger** of your live priced-parts sum and any
    /// documented lump sum. Priced parts win once they meet or exceed the documented figure, so
    /// editing a part cost moves the total (the bug that started this). But a larger documented total
    /// stands as the truth while parts are only partly priced — it covers spend the priced parts
    /// don't yet (unpriced parts, labor, tax, tuning), so pricing one wheel can't collapse a $25k
    /// build to $150.
    public var totalInvested: Double {
        max(itemizedPartsCost, documentedTotalInvestment ?? 0)
    }

    /// True when the shown total is the live parts-sum — priced parts meet or exceed any documented
    /// lump sum, so editing a part price moves it. False when a larger documented total stands in.
    /// Drives honest "logged" vs "documented" wording.
    public var investmentIsLiveFromParts: Bool {
        itemizedPartsCost > 0 && itemizedPartsCost >= (documentedTotalInvestment ?? 0)
    }

    /// When the live parts-sum is the shown total *and* a meaningfully different documented lump sum
    /// also exists (>= $50 apart), that documented figure — so the UI can reconcile the two instead
    /// of hiding it. Nil when they agree, when nothing's documented, or when the documented total is
    /// itself the shown number.
    public var documentedReconcileFigure: Double? {
        guard investmentIsLiveFromParts, let doc = documentedTotalInvestment, doc > 0,
              abs(doc - itemizedPartsCost) >= 50 else { return nil }
        return doc
    }

    /// When a larger documented total is the shown number, how much of it is accounted for by priced
    /// parts so far — so the UI can say "$X priced so far" rather than implying nothing is priced.
    /// Nil when the parts-sum is itself the total, or when nothing is priced.
    public var pricedPartsSoFar: Double? {
        guard !investmentIsLiveFromParts, itemizedPartsCost > 0,
              let doc = documentedTotalInvestment, doc > itemizedPartsCost else { return nil }
        return itemizedPartsCost
    }

    public var latestPerformance: PerformanceRecord? {
        performanceRecords.sorted { $0.date > $1.date }.first
    }

    /// Dyno records carrying a positive wheel figure (> 0), newest first — the single source every
    /// "measured" claim must read from. A dyno session logged with no value (or a non-positive one)
    /// is not a measurement. Centralized because three separate call sites re-deriving this query is
    /// exactly how a crank figure got labeled "whp" twice. A physically *implausible* figure (a
    /// slipped digit) is not screened here — that's caught non-blockingly at entry by
    /// `dynoAnomaly(proposingWheelHorsepower:)`, mirroring the odometer; once the owner saves it, it
    /// is their record and is shown as logged.
    public var measuredDynoRecords: [PerformanceRecord] {
        performanceRecords
            .filter { $0.type == .dyno && ($0.wheelHorsepower ?? 0) > 0 }
            .sorted { $0.date != $1.date ? $0.date > $1.date : $0.id.uuidString < $1.id.uuidString }
    }

    /// The most recent real dyno measurement, if any.
    public var latestMeasuredDyno: PerformanceRecord? { measuredDynoRecords.first }

    /// The latest *actually measured* wheel horsepower — a dyno record that carries a real number.
    /// This, and only this, may ever be presented as "measured". A dyno session logged with no value
    /// is not a measurement, and must not shadow an earlier real one or dress the factory figure up
    /// as measured (the honesty leak a numberless dyno used to cause).
    public var measuredWheelHorsepower: Double? {
        latestMeasuredDyno?.wheelHorsepower
    }

    /// True only when there is a real measured wheel figure. Gate any "measured" label on this —
    /// never on record *type*, which is true even for a dyno logged without a number.
    public var hasMeasuredPower: Bool { measuredWheelHorsepower != nil }

    /// The best current power figure to show: the measured wheel number if there is one, else the
    /// factory rating. The *label* (measured vs estimated) must come from `hasMeasuredPower`, not from
    /// this — this can be a crank estimate.
    public var currentHorsepowerEstimate: Double? {
        measuredWheelHorsepower ?? factoryHorsepower
    }

    /// Current output expressed **at the wheels**, so it compares apples-to-apples against a wheel-hp
    /// goal: the latest wheel dyno if there is one, else the estimated *stock wheel* baseline. Without
    /// a dyno we can't claim the mods' gains, so this is the honest floor — never the crank figure,
    /// which would overstate progress toward a wheel target. Nil without a factory figure and no dyno.
    public var currentWheelHorsepowerEstimate: Double? {
        measuredWheelHorsepower ?? estimatedStockWheelHP
    }

    public var powerToWeight: Double? {
        guard let hp = currentHorsepowerEstimate, let weight = factoryWeightLbs, hp > 0 else { return nil }
        return weight / hp
    }

    /// The odometer as of the most recent event that recorded one — the vehicle's current mileage,
    /// derived from build history rather than stored separately (so it can't drift out of sync).
    /// Ties break toward the larger reading, since two events on the same day can't lower the odo.
    public var currentMileage: Int? {
        buildEvents
            .compactMap { e in e.mileage.map { (e.date, $0) } }
            .max { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1 < $1.1 }?
            .1
    }

    /// The car's average driving rate in miles/day, learned from odometer-stamped build events —
    /// the span between the earliest and latest readings. Nil until there are at least two readings
    /// on different days showing forward motion (so it can't divide by zero or invent a rate from a
    /// single point). This is what lets the Steward project *when* mileage-based service comes due.
    public var milesPerDay: Double? {
        let readings = buildEvents
            .compactMap { e in e.mileage.map { (date: e.date, miles: $0) } }
            .sorted { $0.date < $1.date }
        guard let first = readings.first, let last = readings.last else { return nil }
        let miles = Double(last.miles - first.miles)
        let days = last.date.timeIntervalSince(first.date) / 86_400
        guard days >= 1, miles > 0 else { return nil }
        return miles / days
    }

    public var lastActivityDate: Date? {
        let dates = buildEvents.map(\.date) + performanceRecords.map(\.date) + notes.map(\.date)
        return dates.max()
    }

    /// A wheel-equivalent estimate of the *stock* output, so a measured wheel dyno can be
    /// compared against it apples-to-apples. If the factory figure is already a wheel number,
    /// it's used as-is; otherwise it's brought down from crank by the drivetrain's typical
    /// loss. Nil without a factory figure.
    public var estimatedStockWheelHP: Double? {
        guard let factory = factoryHorsepower else { return nil }
        if factoryPowerBasis == .measuredWheel { return factory }
        return factory * (1 - drivetrain.typicalLossFraction)
    }

    /// True when the stock-wheel baseline rests on an *assumed* drivetrain loss (drivetrain
    /// unspecified), so the reasoning can say so.
    public var stockWheelBaselineIsAssumed: Bool {
        factoryPowerBasis != .measuredWheel && drivetrain == .unknown
    }

    /// Measured wheel horsepower gained over the estimated stock *wheel* baseline. Requires an
    /// actual wheel dyno — you can't measure a wheel gain without one. Still an estimate,
    /// because the baseline is derived, but now wheel-to-wheel rather than wheel-to-crank.
    public var horsepowerGainedOverStock: Double? {
        guard let dyno = measuredWheelHorsepower,
              let baseline = estimatedStockWheelHP else { return nil }
        let gained = dyno - baseline
        return gained > 0 ? gained : nil
    }

    /// What each wheel-hp gained has cost so far — an efficiency estimate, not a dyno-corrected
    /// figure, but now normalized to a wheel-to-wheel comparison.
    public var costPerHorsepowerGained: Double? {
        guard let gained = horsepowerGainedOverStock, gained > 0, totalInvested > 0 else { return nil }
        return totalInvested / gained
    }

    public var costPerInstalledPart: Double? {
        guard installedPartsCount > 0, totalInvested > 0 else { return nil }
        return totalInvested / Double(installedPartsCount)
    }

    /// Recorded spend grouped by system, highest first — *installed*, priced parts only.
    /// Wishlist parts are planned money (`plannedSpend`), not spend, and removed parts aren't
    /// in the car; counting either here would state money as spent that wasn't. Note this sums
    /// *itemized* part prices, which can differ from `documentedTotalInvestment` (a lump sum).
    public var spendByCategory: [(category: PartCategory, total: Double)] {
        var sums: [PartCategory: Double] = [:]
        for part in parts where part.status == .installed {
            if let cost = part.cost, cost > 0 { sums[part.category, default: 0] += cost }
        }
        return sums.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }
}
