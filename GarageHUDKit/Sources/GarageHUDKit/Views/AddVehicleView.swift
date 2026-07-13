import SwiftUI

struct AddVehicleView: View {
    @Environment(\.dismiss) private var dismiss
    var garageSlot: Int
    /// Passed in explicitly rather than via @EnvironmentObject — environment objects
    /// don't reliably propagate into sheets, which crashed on Save.
    var onSave: (Vehicle) -> Void

    @State private var make = ""
    @State private var model = ""
    @State private var year = Calendar.current.component(.year, from: .now)
    @State private var trim = ""
    @State private var nickname = ""

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((1960...(current + 1)).reversed())
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Make", text: $make)
                TextField("Model", text: $model)
                // Tap to pick a year from a list — no more tapping +/- dozens of times.
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { Text(String($0)).tag($0) }
                }
                TextField("Trim", text: $trim)
                TextField("Nickname", text: $nickname)
            }
            .navigationTitle("Add Vehicle — Bay \(garageSlot)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(make.isEmpty || model.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 320)
        #endif
    }

    private func save() {
        var vehicle = Vehicle(make: make, model: model, year: year, trim: trim, nickname: nickname, garageSlot: garageSlot)
        // Auto-populate drivetrain from the identifiers just entered; owner can override in Specs.
        // Stays .unknown when genuinely ambiguous (e.g. a truck with no 4x4/2wd trim).
        vehicle.drivetrain = Drivetrain.inferred(make: make, model: model, trim: trim)
        onSave(vehicle)
        dismiss()
    }
}
