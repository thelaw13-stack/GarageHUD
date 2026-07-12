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
    /// Categories the owner has explicitly confirmed remain factory/stock (no upgrade). This
    /// is the only thing that lets Steward say a system is *confirmed absent* rather than
    /// merely undocumented.
    public var confirmedStockSystems: Set<PartCategory> = []
    /// A per-vehicle override of the live operating limits. When nil, a default envelope is
    /// derived from the record (see `OperatingEnvelope.default(for:)`).
    public var operatingEnvelopeOverride: OperatingEnvelope?
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

    /// Wheel/crank horsepower gained over the factory rating, from the latest dyno pull.
    /// Comparing a dyno'd WHP figure against a crank-rated factory number is approximate —
    /// this is a build-tracking estimate, not a lab-grade before/after measurement.
    public var horsepowerGainedOverStock: Double? {
        guard let current = currentHorsepowerEstimate, let factory = factoryHorsepower else { return nil }
        let gained = current - factory
        return gained > 0 ? gained : nil
    }

    /// What each horsepower gained over stock has cost so far — a rough efficiency read on
    /// the money spent, not a precise dyno-corrected figure.
    public var costPerHorsepowerGained: Double? {
        guard let gained = horsepowerGainedOverStock, gained > 0, totalInvested > 0 else { return nil }
        return totalInvested / gained
    }

    public var costPerInstalledPart: Double? {
        guard installedPartsCount > 0, totalInvested > 0 else { return nil }
        return totalInvested / Double(installedPartsCount)
    }
}
