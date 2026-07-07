import SwiftUI

struct SpecSheetView: View {
    @Binding var vehicle: Vehicle
    var onDelete: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HUDPanel(title: "Vehicle Identity") {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            labeledField("Nickname", text: $vehicle.nickname)
                            yearField
                        }
                        HStack(spacing: 10) {
                            labeledField("Make", text: $vehicle.make)
                            labeledField("Model", text: $vehicle.model)
                        }
                        HStack(spacing: 10) {
                            labeledField("Trim", text: $vehicle.trim)
                            labeledField("Color", text: $vehicle.colorName)
                        }
                    }
                }

                HUDPanel(title: "Factory Baseline") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                        editableStat(label: "Horsepower", value: $vehicle.factoryHorsepower, unit: "HP")
                        editableStat(label: "Torque", value: $vehicle.factoryTorque, unit: "LB-FT")
                        editableStat(label: "Weight", value: $vehicle.factoryWeightLbs, unit: "LBS")
                    }
                    HStack(spacing: 12) {
                        TextField("Engine", text: $vehicle.engineDescription)
                        TextField("Drivetrain", text: $vehicle.drivetrainDescription)
                    }
                    .font(HUDTheme.monoFont(12))
                    .textFieldStyle(.roundedBorder)
                    .padding(.top, 4)
                }

                HUDPanel(title: "Investment") {
                    VStack(alignment: .leading, spacing: 12) {
                        editableStat(label: "Documented Total", value: $vehicle.documentedTotalInvestment, unit: "USD", color: HUDTheme.green)
                        Text("Use this for a known lump-sum figure from a build sheet — it overrides the sum of itemized part costs below wherever \"Total Invested\" is shown.")
                            .font(HUDTheme.monoFont(9))
                            .foregroundStyle(HUDTheme.textSecondary)
                        if vehicle.itemizedPartsCost > 0 {
                            StatReadout(label: "Itemized Parts Cost", value: vehicle.itemizedPartsCost.formatted(.currency(code: "USD")), color: HUDTheme.textSecondary)
                        }
                    }
                }

                HUDPanel(title: "Efficiency") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 16) {
                        if let costPerHP = vehicle.costPerHorsepowerGained {
                            StatReadout(
                                label: "Cost per WHP Gained",
                                value: costPerHP.formatted(.currency(code: "USD")),
                                unit: "/hp",
                                color: HUDTheme.purple
                            )
                        }
                        if let gained = vehicle.horsepowerGainedOverStock {
                            StatReadout(label: "WHP Gained over Stock", value: "+\(Int(gained))", unit: "HP", color: HUDTheme.danger)
                        }
                        if let costPerPart = vehicle.costPerInstalledPart {
                            StatReadout(
                                label: "Avg Cost per Mod",
                                value: costPerPart.formatted(.currency(code: "USD")),
                                color: HUDTheme.amber
                            )
                        }
                    }
                    if vehicle.costPerHorsepowerGained == nil && vehicle.costPerInstalledPart == nil {
                        Text("Set a factory horsepower baseline, log a dyno pull, and a documented total to see cost-efficiency numbers here.")
                            .font(HUDTheme.monoFont(10))
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                }

                HUDPanel(title: "Current Estimated") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 16)], spacing: 16) {
                        if let hp = vehicle.currentHorsepowerEstimate {
                            StatReadout(label: "Horsepower", value: "\(Int(hp))", unit: "HP", color: HUDTheme.cyan)
                        }
                        if let ratio = vehicle.powerToWeight {
                            StatReadout(label: "Power/Weight", value: String(format: "%.2f", ratio), unit: "lb/hp", color: HUDTheme.amber)
                        }
                        StatReadout(label: "Total Invested", value: vehicle.totalInvested.formatted(.currency(code: "USD")), color: HUDTheme.green)
                        StatReadout(label: "Build Complete", value: String(format: "%.0f", vehicle.buildCompletionPercent), unit: "%")
                    }
                }

                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete Vehicle", systemImage: "trash")
                        .font(HUDTheme.monoFont(12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(HUDButtonStyle(color: HUDTheme.danger))
                .padding(.top, 8)
            }
            .padding(24)
        }
        .background(HUDTheme.background)
        .confirmationDialog("Delete \(vehicle.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(vehicle.displayName)", role: .destructive) { onDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the vehicle and all its parts, notes, photos, and records — on every device. This can't be undone.")
        }
    }

    private var years: [Int] {
        let current = Calendar.current.component(.year, from: .now)
        return Array((1960...(current + 1)).reversed())
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(HUDTheme.monoFont(9))
                .foregroundStyle(HUDTheme.textSecondary)
            TextField(label, text: text)
                .font(HUDTheme.monoFont(13, weight: .medium))
                .foregroundStyle(HUDTheme.textPrimary)
                .textFieldStyle(.roundedBorder)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var yearField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("YEAR")
                .font(HUDTheme.monoFont(9))
                .foregroundStyle(HUDTheme.textSecondary)
            Picker("Year", selection: $vehicle.year) {
                ForEach(years, id: \.self) { Text(String($0)).tag($0) }
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.menu)
            #endif
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func editableStat(label: String, value: Binding<Double?>, unit: String, color: Color = HUDTheme.cyan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(HUDTheme.monoFont(9))
                .foregroundStyle(HUDTheme.textSecondary)
            TextField(unit, text: Binding(
                get: { value.wrappedValue.map { String(format: "%g", $0) } ?? "" },
                set: { value.wrappedValue = Double($0) }
            ))
            .font(HUDTheme.monoFont(16, weight: .semibold))
            .foregroundStyle(color)
            .textFieldStyle(.plain)
        }
    }
}
