import SwiftUI

/// A wide hero image for the top of a car's dashboard, showing its chosen cover photo full-bleed.
/// Loads the full-resolution image off the main actor once and caches it in state (rather than
/// decoding the tiny card thumbnail, which would look soft at this size). Renders nothing when the
/// car has no photo, so a photo-less car simply shows no banner.
struct HeroBannerView: View {
    let photo: Photo?
    var height: CGFloat = 170

    @State private var image: PlatformImage?
    @State private var loadedFilename: String?

    var body: some View {
        Group {
            if let image {
                #if canImport(AppKit)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                Color.clear
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(maxWidth: .infinity)
        .frame(height: photo == nil ? 0 : height)
        .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius))
        // A soft bottom gradient so any overlaid text stays legible over bright photos.
        .overlay(alignment: .bottom) {
            if image != nil {
                LinearGradient(colors: [.clear, HUDTheme.background.opacity(0.6)],
                               startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius))
                    .allowsHitTesting(false)
            }
        }
        .task(id: photo?.filename) { await load() }
    }

    private func load() async {
        guard let photo else { image = nil; loadedFilename = nil; return }
        guard photo.filename != loadedFilename else { return }   // already loaded this file
        let filename = photo.filename
        let decoded: PlatformImage? = await Task.detached(priority: .userInitiated) {
            guard let data = ImageStore.load(filename: filename) else { return nil }
            return PlatformImage(data: data)
        }.value
        image = decoded
        loadedFilename = filename
    }
}
