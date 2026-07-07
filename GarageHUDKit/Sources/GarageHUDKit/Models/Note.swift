import Foundation

public struct Note: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var date: Date = .now
    public var title: String
    public var body: String = ""
    public var relatedPartID: UUID?
    public var relatedBuildEventID: UUID?

    public init(
        id: UUID = UUID(),
        date: Date = .now,
        title: String,
        body: String = "",
        relatedPartID: UUID? = nil,
        relatedBuildEventID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.body = body
        self.relatedPartID = relatedPartID
        self.relatedBuildEventID = relatedBuildEventID
    }
}
