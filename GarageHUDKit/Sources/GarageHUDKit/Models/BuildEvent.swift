import Foundation

public struct BuildEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = .now
    public var title: String
    public var eventDescription: String = ""
    public var mileage: Int?
    public var relatedPartIDs: [UUID] = []
    public var photos: [Photo] = []

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        eventDescription: String = "",
        mileage: Int? = nil,
        relatedPartIDs: [UUID] = [],
        photos: [Photo] = []
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.eventDescription = eventDescription
        self.mileage = mileage
        self.relatedPartIDs = relatedPartIDs
        self.photos = photos
    }
}
