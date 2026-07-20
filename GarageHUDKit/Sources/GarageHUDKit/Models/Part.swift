import Foundation

public struct Part: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var name: String
    public var category: PartCategory
    public var brand: String = ""
    public var partNumber: String = ""
    public var status: PartStatus = .installed
    public var installDate: Date?
    public var removeDate: Date?
    public var cost: Double?
    public var vendor: String = ""
    public var notes: String = ""
    public var photos: [Photo] = []
    /// Flagged for attention during a rebuild — needs inspection, replacement, or reorder.
    public var flaggedForRebuild: Bool = false
    /// Edit ordering for this record (ADR-0005). Nil means unstamped — treated as `SyncStamp.zero`,
    /// so a legacy record loses to a deliberate edit and two unstamped sides fall back to today's
    /// adopt-side-wins behaviour.
    public var stamp: SyncStamp? = nil

    public init(
        id: UUID = UUID(),
        name: String,
        category: PartCategory,
        brand: String = "",
        partNumber: String = "",
        status: PartStatus = .installed,
        installDate: Date? = nil,
        removeDate: Date? = nil,
        cost: Double? = nil,
        vendor: String = "",
        notes: String = "",
        photos: [Photo] = [],
        flaggedForRebuild: Bool = false
    ) {
        self.id = id
        self.name = name
        self.category = category
        self.brand = brand
        self.partNumber = partNumber
        self.status = status
        self.installDate = installDate
        self.removeDate = removeDate
        self.cost = cost
        self.vendor = vendor
        self.notes = notes
        self.photos = photos
        self.flaggedForRebuild = flaggedForRebuild
    }

    // Tolerant decoding: missing keys fall back to defaults so older records (and any field
    // added over time) decode cleanly. Swift's *synthesized* Decodable does NOT apply property
    // defaults for absent keys, so this must be explicit.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = try c.decodeIfPresent(PartCategory.self, forKey: .category) ?? .uncategorized
        brand = try c.decodeIfPresent(String.self, forKey: .brand) ?? ""
        partNumber = try c.decodeIfPresent(String.self, forKey: .partNumber) ?? ""
        status = try c.decodeIfPresent(PartStatus.self, forKey: .status) ?? .installed
        installDate = try c.decodeIfPresent(Date.self, forKey: .installDate)
        removeDate = try c.decodeIfPresent(Date.self, forKey: .removeDate)
        cost = try c.decodeIfPresent(Double.self, forKey: .cost)
        vendor = try c.decodeIfPresent(String.self, forKey: .vendor) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        photos = try c.decodeIfPresent([Photo].self, forKey: .photos) ?? []
        flaggedForRebuild = try c.decodeIfPresent(Bool.self, forKey: .flaggedForRebuild) ?? false
        // ADR-0005. This decoder is hand-written, so a new field is silently dropped on read
        // unless it is added here — encoding is synthesized and would happily round-trip it out.
        stamp = try c.decodeIfPresent(SyncStamp.self, forKey: .stamp)
    }
}
