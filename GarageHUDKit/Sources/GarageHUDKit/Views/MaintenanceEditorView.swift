import SwiftUI

/// Edit a maintenance item: its name, time interval, and an optional mileage interval (oil every
/// 5,000 mi). When mileage tracking is turned on, the baseline defaults to the vehicle's current
/// odometer so "next due" is meaningful immediately.
struct MaintenanceEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    let itemID: UUID

    @State private var name = ""
    @State private var intervalMonths = 6
    @State private var trackMiles = false
    @State private var intervalMilesText = "5000"
    @State private var baselineText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Item") {
                    TextField("Name", text: $name)
                }
                Section("Time interval") {
                    Stepper("Every \(intervalMonths) month\(intervalMonths == 1 ? "" : "s")",
                            value: $intervalMonths, in: 1...60)
                }
                Section("Mileage interval") {
                    Toggle("Also track by mileage", isOn: $trackMiles)
                    if trackMiles {
                        HStack {
                            Text("Every")
                            TextField("5000", text: $intervalMilesText)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                            Text("mi")
                        }
                        HStack {
                            Text("Last serviced at")
                            TextField("odometer", text: $baselineText)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                                .multilineTextAlignment(.trailing)
                            Text("mi")
                        }
                    }
                }
            }
            .navigationTitle("Maintenance")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
        .onAppear(perform: populate)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func populate() {
        guard let item = vehicle.maintenance.first(where: { $0.id == itemID }) else { return }
        name = item.name
        intervalMonths = item.intervalMonths
        if let miles = item.intervalMiles {
            trackMiles = true
            intervalMilesText = String(miles)
        }
        // Baseline: the recorded one, else the current odometer as a sensible default.
        baselineText = (item.lastServicedMileage ?? vehicle.currentMileage).map(String.init) ?? ""
    }

    private func save() {
        guard let i = vehicle.maintenance.firstIndex(where: { $0.id == itemID }) else { dismiss(); return }
        vehicle.maintenance[i].name = name
        vehicle.maintenance[i].intervalMonths = intervalMonths
        if trackMiles, let miles = Int(intervalMilesText), miles > 0 {
            vehicle.maintenance[i].intervalMiles = miles
            vehicle.maintenance[i].lastServicedMileage = Int(baselineText) ?? vehicle.currentMileage
        } else {
            vehicle.maintenance[i].intervalMiles = nil
            vehicle.maintenance[i].lastServicedMileage = nil
        }
        dismiss()
    }
}
