import Foundation

/// Rollback information carried by an automatically logged service event. Keeping the prior
/// baseline with the event lets an accidental "Mark done" be truly undone: both the visible
/// history and the maintenance due calculation return to their previous state.
public struct ServiceRecordLink: Codable, Hashable, Sendable {
    public var maintenanceItemID: UUID
    public var previousServicedAt: Date
    public var previousServicedMileage: Int?

    public init(maintenanceItemID: UUID, previousServicedAt: Date,
                previousServicedMileage: Int?) {
        self.maintenanceItemID = maintenanceItemID
        self.previousServicedAt = previousServicedAt
        self.previousServicedMileage = previousServicedMileage
    }
}

public struct BuildEvent: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = .now
    public var title: String
    public var eventDescription: String = ""
    public var mileage: Int?
    public var relatedPartIDs: [UUID] = []
    public var photos: [Photo] = []
    public var serviceRecord: ServiceRecordLink?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        eventDescription: String = "",
        mileage: Int? = nil,
        relatedPartIDs: [UUID] = [],
        photos: [Photo] = [],
        serviceRecord: ServiceRecordLink? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.eventDescription = eventDescription
        self.mileage = mileage
        self.relatedPartIDs = relatedPartIDs
        self.photos = photos
        self.serviceRecord = serviceRecord
    }
}
