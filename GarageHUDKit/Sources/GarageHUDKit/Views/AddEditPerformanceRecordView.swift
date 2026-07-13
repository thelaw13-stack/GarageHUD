import SwiftUI

struct AddEditPerformanceRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    /// nil = adding a new record; otherwise edit the matching record in place.
    var recordID: UUID?

    @State private var type: PerformanceType = .dyno
    @State private var date = Date.now
    @State private var whpText = ""
    @State private var wtqText = ""
    @State private var etText = ""
    @State private var trapText = ""
    @State private var lapText = ""
    @State private var location = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $type) {
                    ForEach(PerformanceType.allCases) { Text($0.rawValue).tag($0) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)

                switch type {
                case .dyno:
                    numberField("Wheel HP", text: $whpText, unit: "whp")
                    numberField("Wheel Torque", text: $wtqText, unit: "lb-ft")
                case .quarterMile:
                    numberField("ET", text: $etText, unit: "sec")
                    numberField("Trap Speed", text: $trapText, unit: "mph")
                case .zeroToSixty:
                    numberField("0-60 Time", text: $etText, unit: "sec")
                case .lapTime:
                    numberField("Lap Time", text: $lapText, unit: "sec")
                case .boostLog:
                    numberField("Peak Boost", text: $trapText, unit: "psi")
                case .custom:
                    EmptyView()
                }

                TextField("Location / Venue", text: $location)
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 70)
                }
            }
            .navigationTitle(recordID == nil ? "Add Performance Record" : "Edit Record")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!hasValue) }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 440)
        #endif
        .onAppear(perform: populateIfEditing)
    }

    @ViewBuilder
    private func numberField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            TextField(label, text: text)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Text(unit).font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
        }
    }

    /// At least one measured value must be present, so we never save an empty record
    /// that shows as a blank card (the bug that produced a "0 whp" ghost entry before).
    private var hasValue: Bool {
        switch type {
        case .dyno: return Double(whpText) != nil || Double(wtqText) != nil
        case .quarterMile: return Double(etText) != nil || Double(trapText) != nil
        case .zeroToSixty: return Double(etText) != nil
        case .lapTime: return Double(lapText) != nil
        case .boostLog: return Double(trapText) != nil || !notes.isEmpty
        case .custom: return !notes.isEmpty || !location.isEmpty
        }
    }

    private func populateIfEditing() {
        guard let recordID, let r = vehicle.performanceRecords.first(where: { $0.id == recordID }) else { return }
        type = r.type
        date = r.date
        whpText = r.wheelHorsepower.map { String(Int($0)) } ?? ""
        wtqText = r.wheelTorque.map { String(Int($0)) } ?? ""
        etText = r.elapsedTimeSeconds.map { String($0) } ?? ""
        trapText = r.trapSpeedMph.map { String($0) } ?? ""
        lapText = r.lapTimeSeconds.map { String($0) } ?? ""
        location = r.location
        notes = r.notes
    }

    private func save() {
        var record = recordID.flatMap { id in vehicle.performanceRecords.first { $0.id == id } }
            ?? PerformanceRecord(type: type)
        record.type = type
        record.date = date
        record.wheelHorsepower = Double(whpText)
        record.wheelTorque = Double(wtqText)
        record.elapsedTimeSeconds = Double(etText)
        record.trapSpeedMph = Double(trapText)
        record.lapTimeSeconds = Double(lapText)
        record.location = location
        record.notes = notes

        if let index = vehicle.performanceRecords.firstIndex(where: { $0.id == record.id }) {
            vehicle.performanceRecords[index] = record
        } else {
            vehicle.performanceRecords.append(record)
        }
        dismiss()
    }
}
