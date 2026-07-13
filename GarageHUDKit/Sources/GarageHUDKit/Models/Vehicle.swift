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

    public var parts: [Part] = []
    public var buildEvents: [BuildEvent] = []
    public var performanceRecords: [PerformanceRecord] = []
    public var notes: [Note] = []
    public var photos: [Photo] = []
    public var maintenance: [MaintenanceItem] = []

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
        confirmedStockSystems = try c.decodeIfPresent(Set<PartCategory>.self, forKey: .confirmedStockSystems) ?? []
        operatingEnvelopeOverride = try c.decodeIfPresent(OperatingEnvelope.self, forKey: .operatingEnvelopeOverride)
        serviceStatus = try c.decodeIfPresent(ServiceStatus.self, forKey: .serviceStatus) ?? .operational
        parts = try c.decodeIfPresent([Part].self, forKey: .parts) ?? []
        buildEvents = try c.decodeIfPresent([BuildEvent].self, forKey: .buildEvents) ?? []
        performanceRecords = try c.decodeIfPresent([PerformanceRecord].self, forKey: .performanceRecords) ?? []
        notes = try c.decodeIfPresent([Note].self, forKey: .notes) ?? []
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
        maintenance = try c.decodeIfPresent([MaintenanceItem].self, forKey: .maintenance) ?? []
    }

    /// Title prefix marking a build event as a completed service, so the service log can be
    /// distinguished from the rest of the biography without a separate event type.
    public static let servicePrefix = "Serviced: "

    /// Record a maintenance item as done: reset its interval and log it to the biography so the
    /// service history is preserved (and shows on the timeline / in the export).
    public mutating func markMaintenanceDone(_ id: UUID, on date: Date = .now) {
        guard let i = maintenance.firstIndex(where: { $0.id == id }) else { return }
        maintenance[i].lastServiced = date
        // Re-baseline the mileage interval too, so "every 5,000 mi" counts from the current odometer.
        if maintenance[i].intervalMiles != nil, let odo = currentMileage {
            maintenance[i].lastServicedMileage = odo
        }
        let odoNote = currentMileage.map { " @ \($0.formatted(.number.grouping(.automatic))) mi" } ?? ""
        buildEvents.append(BuildEvent(date: date, title: "\(Vehicle.servicePrefix)\(maintenance[i].name)\(odoNote)",
                                      mileage: currentMileage))
    }

    /// The card/hero photo: the vehicle's own first photo, else the most recent build-event photo,
    /// so a car with any photography at all has a face on the garage grid.
    public var heroPhoto: Photo? {
        photos.first ?? buildEvents.sorted { $0.date > $1.date }.flatMap(\.photos).first
    }

    /// Completed services, newest first — the maintenance record distilled from the biography.
    public var serviceLog: [BuildEvent] {
        buildEvents.filter { $0.title.hasPrefix(Vehicle.servicePrefix) }
            .sorted { $0.date > $1.date }
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

    public var itemizedPartsCost: Double {
        parts.compactMap { $0.status == .removed ? nil : $0.cost }.reduce(0, +)
    }

    /// The number to show as "total invested" — prefers a documented lump-sum figure
    /// (from a build sheet) over the sum of itemized part costs, since most parts here
    /// don't have individual prices recorded.
    public var totalInvested: Double {
        documentedTotalInvestment ?? itemizedPartsCost
    }

    public var latestPerformance: PerformanceRecord? {
        performanceRecords.sorted { $0.date > $1.date }.first
    }

    public var currentHorsepowerEstimate: Double? {
        performanceRecords
            .filter { $0.type == .dyno }
            .sorted { $0.date > $1.date }
            .first?
            .wheelHorsepower ?? factoryHorsepower
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
        guard let dyno = performanceRecords
                .filter({ $0.type == .dyno && $0.wheelHorsepower != nil })
                .sorted(by: { $0.date > $1.date }).first?.wheelHorsepower,
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

    /// Recorded spend grouped by system, highest first — only categories with priced parts
    /// (removed parts and undocumented-price parts are excluded). Note this sums *itemized*
    /// part prices, which can differ from `documentedTotalInvestment` (a lump-sum figure).
    public var spendByCategory: [(category: PartCategory, total: Double)] {
        var sums: [PartCategory: Double] = [:]
        for part in parts where part.status != .removed {
            if let cost = part.cost, cost > 0 { sums[part.category, default: 0] += cost }
        }
        return sums.map { (category: $0.key, total: $0.value) }.sorted { $0.total > $1.total }
    }
}
