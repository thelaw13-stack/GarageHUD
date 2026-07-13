import SwiftUI

struct GalleryView: View {
    @Binding var vehicle: Vehicle
    @State private var selectedPhoto: Photo?

    /// Photos added directly to the vehicle here are editable/removable; photos that came
    /// in via a part or build event are shown too but managed from those screens.
    private var directPhotos: [Photo] { vehicle.photos.sorted { $0.date > $1.date } }
    private var linkedPhotos: [Photo] {
        (vehicle.parts.flatMap(\.photos) + vehicle.buildEvents.flatMap(\.photos)).sorted { $0.date > $1.date }
    }
    private var allPhotos: [Photo] { (directPhotos + linkedPhotos) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("GALLERY")
                        .font(HUDTheme.label(.semibold))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .tracking(2)
                    Spacer()
                    PhotoAddButton { data in addPhoto(data) }
                }
                .padding(.horizontal).padding(.top)

                if allPhotos.isEmpty {
                    VStack(spacing: 6) {
                        Spacer(minLength: 80)
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 30)).foregroundStyle(HUDTheme.textSecondary)
                        Text("No photos yet — tap Add Photos above.")
                            .font(HUDTheme.body())
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(allPhotos) { photo in
                            thumbnail(photo)
                                .onTapGesture { selectedPhoto = photo }
                                .contextMenu {
                                    if vehicle.coverPhotoID == photo.id {
                                        Button("Remove as Cover") { vehicle.setCover(nil) }
                                    } else {
                                        Button("Set as Cover") { vehicle.setCover(photo.id) }
                                    }
                                    if vehicle.photos.contains(where: { $0.id == photo.id }) {
                                        Button("Delete Photo", role: .destructive) { removePhoto(photo) }
                                    }
                                }
                                .overlay(alignment: .topLeading) {
                                    if vehicle.coverPhotoID == photo.id {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 11)).foregroundStyle(.white)
                                            .padding(4)
                                            .background(HUDTheme.cyan, in: Circle())
                                            .padding(6)
                                    }
                                }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .background(HUDTheme.background)
        #if os(iOS)
        // Full-screen viewer: no sheet swipe-to-dismiss competing with pinch/pan.
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, onRename: { caption in renamePhoto(id: photo.id, caption: caption) })
        }
        #else
        .sheet(item: $selectedPhoto) { photo in
            PhotoDetailView(photo: photo, onRename: { caption in renamePhoto(id: photo.id, caption: caption) })
        }
        #endif
    }

    private func addPhoto(_ data: Data) {
        guard let photo = ImageStore.makePhoto(from: data) else { return }
        vehicle.photos.append(photo)
    }

    private func removePhoto(_ photo: Photo) {
        vehicle.photos.removeAll { $0.id == photo.id }
        ImageStore.delete(filename: photo.filename)
    }

    /// Updates a photo's caption/name wherever it lives (directly on the vehicle, or on a
    /// part or build event), matched by stable id so the right image is edited.
    private func renamePhoto(id: UUID, caption: String) {
        if let i = vehicle.photos.firstIndex(where: { $0.id == id }) {
            vehicle.photos[i].caption = caption; return
        }
        for pi in vehicle.parts.indices {
            if let i = vehicle.parts[pi].photos.firstIndex(where: { $0.id == id }) {
                vehicle.parts[pi].photos[i].caption = caption; return
            }
        }
        for bi in vehicle.buildEvents.indices {
            if let i = vehicle.buildEvents[bi].photos.firstIndex(where: { $0.id == id }) {
                vehicle.buildEvents[bi].photos[i].caption = caption; return
            }
        }
    }

    @ViewBuilder
    private func thumbnail(_ photo: Photo) -> some View {
        Group {
            if let image = ImageStore.thumbnailImage(for: photo) {
                #if canImport(AppKit)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                Rectangle().fill(HUDTheme.panelBackground)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(height: 140)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))
    }
}

private struct PhotoDetailView: View {
    var photo: Photo
    var onRename: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String = ""

    private var fullImage: PlatformImage? {
        guard let data = ImageStore.load(filename: photo.filename) else { return nil }
        return PlatformImage(data: data)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Spacer()
                Button {
                    saveAndClose()
                } label: {
                    Label("Close", systemImage: "xmark.circle.fill")
                        .font(HUDTheme.body(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HUDTheme.textSecondary)
                .keyboardShortcut(.cancelAction)
            }

            if let image = fullImage {
                ZoomableImage(image: image)
            } else {
                // Full-res file missing/unreadable — show a fallback instead of an empty modal.
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundStyle(HUDTheme.textSecondary)
                    Text("Image file could not be loaded.")
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 8) {
                Image(systemName: "textformat").foregroundStyle(HUDTheme.textSecondary)
                TextField("Name this photo…", text: $caption)
                    .textFieldStyle(.plain)
                    .font(HUDTheme.body())
                    .onSubmit { onRename(caption) }
            }
            .padding(10)
            .background(HUDTheme.panelBackground)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDTheme.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 500, idealWidth: 720, minHeight: 460, idealHeight: 620)
        #endif
        .onAppear { caption = photo.caption }
    }

    private func saveAndClose() {
        onRename(caption)
        dismiss()
    }
}

/// Pinch-to-zoom + pan photo viewer. Double-tap toggles between fit and 2.5×.
/// Works on iOS (pinch) and macOS (trackpad pinch).
private struct ZoomableImage: View {
    let image: PlatformImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private var imageView: Image {
        #if canImport(AppKit)
        Image(nsImage: image)
        #else
        Image(uiImage: image)
        #endif
    }

    var body: some View {
        imageView
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .offset(offset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        scale = min(max(1, lastScale * value), 6)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= 1 {
                            withAnimation(.easeOut(duration: 0.2)) { offset = .zero; lastOffset = .zero }
                        }
                    }
                    .simultaneously(with:
                        DragGesture()
                            .onChanged { value in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + value.translation.width,
                                                height: lastOffset.height + value.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if scale > 1 {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    } else {
                        scale = 2.5; lastScale = 2.5
                    }
                }
            }
            .clipped()
    }
}
