import Foundation

public enum PartCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case engine = "Engine"
    case forcedInduction = "Forced Induction"
    case drivetrain = "Drivetrain"
    case suspension = "Suspension"
    case brakes = "Brakes"
    case wheelsAndTires = "Wheels & Tires"
    case exhaust = "Exhaust"
    case fueling = "Fueling"
    case cooling = "Cooling"
    case exterior = "Exterior"
    case interior = "Interior"
    case electronics = "Electronics"
    case uncategorized = "Uncategorized"

    public var id: String { rawValue }
}

public enum PartStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case installed = "Installed"
    case removed = "Removed"
    case wishlist = "Wishlist"

    public var id: String { rawValue }
}

public enum PerformanceType: String, Codable, CaseIterable, Identifiable, Sendable {
    case dyno = "Dyno"
    case quarterMile = "Quarter Mile"
    case zeroToSixty = "0-60"
    case lapTime = "Lap Time"
    case boostLog = "Boost Log"
    case custom = "Custom"

    public var id: String { rawValue }
}
