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
        photos: [Photo] = []
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
    }
}
