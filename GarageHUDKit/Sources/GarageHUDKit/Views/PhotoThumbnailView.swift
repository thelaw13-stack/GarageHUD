import SwiftUI

/// A cached photo thumbnail, filling a square/rect frame. Platform-guarded so the same view works
/// on macOS (NSImage) and iOS (UIImage). Falls back to a car glyph when there's no photo.
struct PhotoThumbnailView: View {
    let photo: Photo?
    var vehicle: Vehicle?
    var size: CGFloat = 52

    var body: some View {
        Group {
            if let photo, let image = ImageStore.thumbnailImage(for: photo) {
                #if canImport(AppKit)
                Image(nsImage: image).resizable()
                #else
                    Image(uiImage: image).resizable()
                #endif
            } else {
                VehicleVisualFallback(vehicle: vehicle, style: .thumbnail)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
    }
}
