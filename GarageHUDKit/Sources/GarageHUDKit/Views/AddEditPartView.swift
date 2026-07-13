import SwiftUI

struct AddEditPartView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var vehicle: Vehicle
    var partID: UUID?

    @State private var name = ""
    @State private var category: PartCategory = .engine
    @State private var brand = ""
    @State private var partNumber = ""
    @State private var status: PartStatus = .installed
    @State private var installDate = Date.now
    @State private var costText = ""
    @State private var vendor = ""
    @State private var notes = ""
    @State private var flaggedForRebuild = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(PartCategory.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(PartStatus.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Brand", text: $brand)
                    TextField("Part Number", text: $partNumber)
                }
                Section("Purchase") {
                    DatePicker("Install Date", selection: $installDate, displayedComponents: .date)
                    TextField("Cost", text: $costText)
                    TextField("Vendor", text: $vendor)
                }
                Section("Rebuild") {
                    Toggle("Flag for replacement / reorder", isOn: $flaggedForRebuild)
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 80)
                }
            }
            .navigationTitle(partID == nil ? "Add Part" : "Edit Part")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(name.isEmpty)
                }
            }
        }
        .onAppear(perform: populateIfEditing)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func populateIfEditing() {
        guard let partID, let part = vehicle.parts.first(where: { $0.id == partID }) else { return }
        name = part.name
        category = part.category
        brand = part.brand
        partNumber = part.partNumber
        status = part.status
        installDate = part.installDate ?? .now
        costText = part.cost.map { String($0) } ?? ""
        vendor = part.vendor
        notes = part.notes
        flaggedForRebuild = part.flaggedForRebuild
    }

    private func save() {
        let cost = Double(costText)
        var part = partID.flatMap { id in vehicle.parts.first { $0.id == id } } ?? Part(name: name, category: category)
        part.name = name
        part.category = category
        part.brand = brand
        part.partNumber = partNumber
        part.status = status
        part.installDate = installDate
        part.cost = cost
        part.vendor = vendor
        part.notes = notes
        part.flaggedForRebuild = flaggedForRebuild

        if let index = vehicle.parts.firstIndex(where: { $0.id == part.id }) {
            vehicle.parts[index] = part
        } else {
            vehicle.parts.append(part)
        }
        dismiss()
    }
}
