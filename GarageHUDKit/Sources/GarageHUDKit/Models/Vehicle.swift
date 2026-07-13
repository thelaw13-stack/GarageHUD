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

    public var displayName: String {
        nickname.isEmpty ? "\(year) \(make) \(model)" : nickname
    }

    public var subtitle: String {
        "\(year) \(make) \(model)\(trim.isEmpty ? "" : " \(trim)")"
    }

    public var installedPartsCount: Int {
        parts.filter { $0.status == .installed }.count
    }

    public var wishlistPartsCount: Int {
        parts.filter { $0.status == .wishlist }.count
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
