import SwiftUI

struct NotesView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAdd = false
    @State private var editingNote: Note?

    private var notes: [Note] {
        vehicle.notes.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("NOTES")
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .tracking(2)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Label("New Note", systemImage: "plus")
                }
                .buttonStyle(.primaryAction)
            }
            .padding()

            if notes.isEmpty {
                Spacer()
                Text("No notes yet.")
                    .font(HUDTheme.body())
                    .foregroundStyle(HUDTheme.textSecondary)
                Spacer()
            } else {
                List {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.title)
                                    .font(HUDTheme.body(.medium))
                                    .foregroundStyle(HUDTheme.textPrimary)
                                Spacer()
                                Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(HUDTheme.label())
                                    .foregroundStyle(HUDTheme.textSecondary)
                            }
                            if !note.body.isEmpty {
                                Text(note.body)
                                    .font(HUDTheme.label())
                                    .foregroundStyle(HUDTheme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { editingNote = note }
                    }
                    .onDelete { indexSet in
                        vehicle.deleteNotes(Set(indexSet.map { notes[$0].id }))
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAdd) {
            AddEditNoteView(vehicle: $vehicle, noteID: nil)
        }
        .sheet(item: $editingNote) { note in
            AddEditNoteView(vehicle: $vehicle, noteID: note.id)
        }
    }
}
