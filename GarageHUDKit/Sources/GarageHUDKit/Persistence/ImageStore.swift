import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
#elseif canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#endif

/// Stores full-resolution photos as files (Application Support) and hands back
/// small thumbnail Data blobs that are cheap to keep inline in SwiftData.
public enum ImageStore {
    // Decoding thumbnail Data → image on every SwiftUI re-render is what made editors with
    // photo strips feel sluggish. Cache decoded thumbnails by photo id (NSCache is thread-safe).
    // NSCache is internally thread-safe, so this shared cache is safe to touch from any
    // thread; the checker can't see that, hence nonisolated(unsafe).
    nonisolated(unsafe) private static let thumbCache = NSCache<NSString, PlatformImage>()

    public static func thumbnailImage(for photo: Photo) -> PlatformImage? {
        let key = photo.id.uuidString as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let data = photo.thumbnailData, let image = PlatformImage(data: data) else { return nil }
        thumbCache.setObject(image, forKey: key)
        return image
    }

    public static var imagesDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GarageHUD", isDirectory: true)
            .appendingPathComponent("Photos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    @discardableResult
    public static func save(imageData: Data, suggestedExtension: String = "jpg") throws -> String {
        let filename = "\(UUID().uuidString).\(suggestedExtension)"
        let url = imagesDirectory.appendingPathComponent(filename)
        try imageData.write(to: url, options: .atomic)
        return filename
    }

    public static func load(filename: String) -> Data? {
        let url = imagesDirectory.appendingPathComponent(filename)
        return try? Data(contentsOf: url)
    }

    /// Writes image data under an exact filename (used when restoring bundled seed
    /// photos whose `Photo.filename` must be preserved so records stay linked).
    public static func writeRaw(filename: String, data: Data) {
        let url = imagesDirectory.appendingPathComponent(filename)
        try? data.write(to: url, options: .atomic)
    }

    public static func exists(filename: String) -> Bool {
        FileManager.default.fileExists(atPath: imagesDirectory.appendingPathComponent(filename).path)
    }

    public static func delete(filename: String) {
        let url = imagesDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    /// Saves the full-res image to disk and returns a ready-to-insert `Photo` with a cached thumbnail.
    public static func makePhoto(from data: Data, caption: String = "") -> Photo? {
        guard let filename = try? save(imageData: data) else { return nil }
        return Photo(filename: filename, thumbnailData: thumbnailData(from: data), caption: caption)
    }

    public static func thumbnailData(from imageData: Data, maxDimension: CGFloat = 300) -> Data? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgThumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgThumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}
