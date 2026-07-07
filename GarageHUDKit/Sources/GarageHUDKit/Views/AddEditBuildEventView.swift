import SwiftUI

struct AddEditBuildEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    var eventID: UUID?

    @State private var title = ""
    @State private var date = Date.now
    @State private var eventDescription = ""
    @State private var mileageText = ""
    @State private var photos: [Photo] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Event") {
                    TextField("Title", text: $title)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    TextField("Mileage", text: $mileageText)
                    TextEditor(text: $eventDescription).frame(minHeight: 80)
                }
                Section("Photos") {
                    PhotoThumbnailStrip(photos: photos, onAdd: addPhoto, onDelete: removePhoto)
                        .frame(height: 80)
                }
            }
            .navigationTitle(eventID == nil ? "Log Build Event" : "Edit Event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
        }
        .onAppear(perform: populateIfEditing)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func populateIfEditing() {
        guard let eventID, let event = vehicle.buildEvents.first(where: { $0.id == eventID }) else { return }
        title = event.title
        date = event.date
        eventDescription = event.eventDescription
        mileageText = event.mileage.map(String.init) ?? ""
        photos = event.photos
    }

    private func addPhoto(_ data: Data) {
        guard let photo = ImageStore.makePhoto(from: data) else { return }
        photos.append(photo)
    }

    private func removePhoto(_ photo: Photo) {
        photos.removeAll { $0.id == photo.id }
        ImageStore.delete(filename: photo.filename)
    }

    private func save() {
        let mileage = Int(mileageText)
        var event = eventID.flatMap { id in vehicle.buildEvents.first { $0.id == id } } ?? BuildEvent(title: title)
        event.title = title
        event.date = date
        event.eventDescription = eventDescription
        event.mileage = mileage
        event.photos = photos

        if let index = vehicle.buildEvents.firstIndex(where: { $0.id == event.id }) {
            vehicle.buildEvents[index] = event
        } else {
            vehicle.buildEvents.append(event)
        }
        dismiss()
    }
}
