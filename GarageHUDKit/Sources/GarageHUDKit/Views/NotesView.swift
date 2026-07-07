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
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(2)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Label("New Note", systemImage: "plus")
                }
                .buttonStyle(HUDButtonStyle())
            }
            .padding()

            if notes.isEmpty {
                Spacer()
                Text("No notes yet.")
                    .font(HUDTheme.monoFont(12))
                    .foregroundStyle(HUDTheme.textSecondary)
                Spacer()
            } else {
                List {
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(note.title)
                                    .font(HUDTheme.monoFont(13, weight: .medium))
                                    .foregroundStyle(HUDTheme.textPrimary)
                                Spacer()
                                Text(note.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(HUDTheme.monoFont(9))
                                    .foregroundStyle(HUDTheme.textSecondary)
                            }
                            if !note.body.isEmpty {
                                Text(note.body)
                                    .font(HUDTheme.monoFont(11))
                                    .foregroundStyle(HUDTheme.textSecondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture { editingNote = note }
                    }
                    .onDelete { indexSet in
                        let idsToDelete = indexSet.map { notes[$0].id }
                        vehicle.notes.removeAll { idsToDelete.contains($0.id) }
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
