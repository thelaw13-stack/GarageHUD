import SwiftUI

struct AddEditNoteView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    var noteID: UUID?

    @State private var title = ""
    @State private var noteBody = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Title", text: $title)
                TextEditor(text: $noteBody).frame(minHeight: 160)
            }
            .navigationTitle(noteID == nil ? "New Note" : "Edit Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(title.isEmpty)
                }
            }
        }
        .onAppear(perform: populateIfEditing)
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 360)
        #endif
    }

    private func populateIfEditing() {
        guard let noteID, let note = vehicle.notes.first(where: { $0.id == noteID }) else { return }
        title = note.title
        noteBody = note.body
    }

    private func save() {
        var note = noteID.flatMap { id in vehicle.notes.first { $0.id == id } } ?? Note(title: title)
        note.title = title
        note.body = noteBody

        if let index = vehicle.notes.firstIndex(where: { $0.id == note.id }) {
            vehicle.notes[index] = note
        } else {
            vehicle.notes.append(note)
        }
        dismiss()
    }
}
