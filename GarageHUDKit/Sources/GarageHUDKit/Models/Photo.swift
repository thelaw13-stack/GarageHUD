import Foundation

public struct Photo: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID = UUID()
    public var filename: String
    public var thumbnailData: Data?
    public var caption: String = ""
    public var date: Date = .now

    public init(
        id: UUID = UUID(),
        filename: String,
        thumbnailData: Data? = nil,
        caption: String = "",
        date: Date = .now
    ) {
        self.id = id
        self.filename = filename
        self.thumbnailData = thumbnailData
        self.caption = caption
        self.date = date
    }
}
