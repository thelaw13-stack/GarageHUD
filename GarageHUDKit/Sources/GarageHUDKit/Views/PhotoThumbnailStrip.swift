import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(PhotosUI)
import PhotosUI
#endif

/// A styled "Add Photos" button that pulls from the camera roll on iOS (multi-select)
/// and a file open panel on macOS. Calls `onAdd` once per chosen image.
struct PhotoAddButton: View {
    var onAdd: (Data) -> Void

    #if !os(macOS)
    @State private var selection: [PhotosPickerItem] = []
    #endif

    var body: some View {
        #if os(macOS)
        Button(action: pickFiles) {
            Label("Add Photos", systemImage: "plus")
        }
        .buttonStyle(.primaryAction)
        #else
        PhotosPicker(selection: $selection, matching: .images) {
            Label("Add Photos", systemImage: "plus")
                .font(HUDTheme.monoFont(12, weight: .semibold))
                .foregroundStyle(HUDTheme.cyan)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(HUDTheme.cyan.opacity(0.6), lineWidth: 1))
        }
        .onChange(of: selection) { _, items in
            guard !items.isEmpty else { return }
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        onAdd(data)
                    }
                }
                selection = []
            }
        }
        #endif
    }

    #if os(macOS)
    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add Photos"
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let data = try? Data(contentsOf: url) { onAdd(data) }
            }
        }
    }
    #endif
}

struct PhotoThumbnailStrip: View {
    var photos: [Photo]
    var onAdd: ((Data) -> Void)?
    var onDelete: ((Photo) -> Void)?

    #if !os(macOS)
    @State private var selectedItem: PhotosPickerItem?
    #endif

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(photos) { photo in
                    thumbnail(for: photo)
                }
                if onAdd != nil {
                    addButton
                }
            }
        }
    }

    // MARK: Add button (platform-specific picker)

    @ViewBuilder
    private var addButton: some View {
        #if os(macOS)
        // NSOpenPanel works in an un-bundled executable; PhotosUI's picker does not
        // (it needs Photos entitlements + a bundle, and crashes the process otherwise).
        Button(action: pickImageFile) {
            addTile
        }
        .buttonStyle(.plain)
        #else
        PhotosPicker(selection: $selectedItem, matching: .images) {
            addTile
        }
        .buttonStyle(.plain)
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self) {
                    onAdd?(data)
                }
                selectedItem = nil
            }
        }
        #endif
    }

    private var addTile: some View {
        RoundedRectangle(cornerRadius: 8)
            .strokeBorder(HUDTheme.cyan.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .frame(width: 70, height: 70)
            .overlay(Image(systemName: "plus").foregroundStyle(HUDTheme.cyan))
    }

    #if os(macOS)
    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        panel.prompt = "Add Photo"
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            onAdd?(data)
        }
    }
    #endif

    // MARK: Thumbnail

    @ViewBuilder
    private func thumbnail(for photo: Photo) -> some View {
        Group {
            if let image = ImageStore.thumbnailImage(for: photo) {
                #if canImport(AppKit)
                Image(nsImage: image).resizable()
                #else
                Image(uiImage: image).resizable()
                #endif
            } else {
                Rectangle().fill(HUDTheme.panelBackground)
                    .overlay(Image(systemName: "photo").foregroundStyle(HUDTheme.textSecondary))
            }
        }
        .aspectRatio(contentMode: .fill)
        .frame(width: 70, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(HUDTheme.cyan.opacity(0.3), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            if let onDelete {
                Button {
                    onDelete(photo)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(3)
            }
        }
    }
}
