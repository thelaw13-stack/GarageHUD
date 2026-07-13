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

                stewardInputsPanel

                liveEnvelopePanel

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

                spendBySystemPanel

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

    @ViewBuilder
    private var spendBySystemPanel: some View {
        let breakdown = vehicle.spendByCategory
        if !breakdown.isEmpty {
            let maxTotal = breakdown.first?.total ?? 1
            HUDPanel(title: "Spend by System") {
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    ForEach(breakdown, id: \.category) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(row.category.rawValue.uppercased())
                                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary).tracking(1)
                                Spacer()
                                Text(row.total.formatted(.currency(code: "USD").precision(.fractionLength(0))))
                                    .font(HUDTheme.body(.medium)).foregroundStyle(HUDTheme.textPrimary)
                            }
                            GeometryReader { geo in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(HUDTheme.cyan.opacity(0.5))
                                    .frame(width: max(2, geo.size.width * CGFloat(row.total / maxTotal)), height: 4)
                            }
                            .frame(height: 4)
                        }
                    }
                    Text("Itemized part prices — undocumented-price parts aren't counted here.")
                        .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
                }
            }
        }
    }

    // MARK: Steward inputs — the fields that sharpen (and keep honest) the reasoning.

    private var stewardInputsPanel: some View {
        HUDPanel(title: "Steward Inputs") {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { vehicle.serviceStatus.isInService },
                    set: { on in
                        vehicle.serviceStatus.isInService = on
                        if on && vehicle.serviceStatus.since == nil { vehicle.serviceStatus.since = Date() }
                    })) {
                    Text("Out of service (teardown / rebuild)")
                        .font(HUDTheme.monoFont(11))
                }
                .hudCheckboxStyle()
                if vehicle.serviceStatus.isInService {
                    TextField("Reason — e.g. engine teardown", text: $vehicle.serviceStatus.reason)
                        .font(HUDTheme.monoFont(11))
                        .textFieldStyle(.roundedBorder)
                    Text("Steward won't flag an out-of-service car as neglected.")
                        .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
                }
                Divider().overlay(HUDTheme.hairline)

                pickerRow("Drivetrain", selection: $vehicle.drivetrain,
                          options: Drivetrain.allCases, label: { $0.displayName })
                Text("Used to estimate driveline loss so cost-per-hp compares wheel-to-wheel.")
                    .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)

                pickerRow("Factory HP basis", selection: $vehicle.factoryPowerBasis,
                          options: PowerBasis.allCases, label: { $0.displayName })

                Divider().overlay(HUDTheme.cyan.opacity(0.2))

                Text("CONFIRMED FACTORY-STOCK SYSTEMS")
                    .font(HUDTheme.monoFont(9, weight: .semibold)).foregroundStyle(HUDTheme.cyan).tracking(1)
                Text("Confirm a system is still stock so Steward can tell a real gap from a merely undocumented one — a confirmed gap is a firm caution; an undocumented one stays weak.")
                    .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
                ForEach([PartCategory.fueling, .cooling, .brakes]) { category in
                    Toggle(isOn: stockBinding(category)) {
                        Text("\(category.rawValue) is factory-stock")
                            .font(HUDTheme.monoFont(11))
                    }
                    .hudCheckboxStyle()
                }
            }
        }
    }

    private var liveEnvelopePanel: some View {
        HUDPanel(title: "Live Envelope & Tune") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Per-vehicle live limits. Boost rules only apply where boost means something.")
                    .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 12) {
                    envField("Coolant caution °F", get: { $0.coolantCautionF }, set: { $0.coolantCautionF = $1 }, color: HUDTheme.amber)
                    envField("Coolant critical °F", get: { $0.coolantCriticalF }, set: { $0.coolantCriticalF = $1 }, color: HUDTheme.danger)
                    envOptField("Boost caution psi", get: { $0.boostCautionPsi }, set: { $0.boostCautionPsi = $1 }, color: HUDTheme.amber)
                    envOptField("Boost ceiling psi", get: { $0.maxSustainedBoostPsi }, set: { $0.maxSustainedBoostPsi = $1 }, color: HUDTheme.danger)
                }
                boostBandsEditor
            }
        }
    }

    private var boostBandsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("RPM-BANDED BOOST TARGETS")
                    .font(HUDTheme.monoFont(9, weight: .semibold)).foregroundStyle(HUDTheme.cyan).tracking(1)
                Spacer()
                Button {
                    var env = vehicle.operatingEnvelope
                    env.expectedBoostByRPM.append(BoostBand(rpmLow: 3000, rpmHigh: 5000, expectedLowPsi: 10, expectedHighPsi: 16))
                    vehicle.operatingEnvelopeOverride = env
                } label: { Image(systemName: "plus.circle").foregroundStyle(HUDTheme.cyan) }
                .buttonStyle(.plain)
            }
            let bands = vehicle.operatingEnvelope.expectedBoostByRPM
            if bands.isEmpty {
                Text("Optional. Add rows to judge boost against your tune at each RPM instead of one threshold.")
                    .font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
            } else {
                ForEach(bands.indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        bandField("rpm", i, \.rpmLow); Text("–").foregroundStyle(HUDTheme.textSecondary)
                        bandField("rpm", i, \.rpmHigh); Text("@").foregroundStyle(HUDTheme.textSecondary)
                        bandPsiField("psi", i, \.expectedLowPsi); Text("–").foregroundStyle(HUDTheme.textSecondary)
                        bandPsiField("psi", i, \.expectedHighPsi)
                        Button { removeBand(i) } label: { Image(systemName: "minus.circle").foregroundStyle(HUDTheme.danger) }
                            .buttonStyle(.plain)
                    }
                    .font(HUDTheme.monoFont(11))
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: Steward-input helpers

    private func pickerRow<T: Hashable & Identifiable>(_ title: String, selection: Binding<T>,
                                                       options: [T], label: @escaping (T) -> String) -> some View {
        HStack {
            Text(title.uppercased()).font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(options) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            #if os(macOS)
            .pickerStyle(.menu)
            #endif
        }
    }

    private func stockBinding(_ category: PartCategory) -> Binding<Bool> {
        Binding(
            get: { vehicle.confirmedStockSystems.contains(category) },
            set: { on in
                if on { vehicle.confirmedStockSystems.insert(category) }
                else { vehicle.confirmedStockSystems.remove(category) }
            }
        )
    }

    private func envField(_ label: String, get: @escaping (OperatingEnvelope) -> Double,
                          set: @escaping (inout OperatingEnvelope, Double) -> Void, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
            TextField("", text: Binding(
                get: { String(format: "%g", get(vehicle.operatingEnvelope)) },
                set: { var env = vehicle.operatingEnvelope; if let v = Double($0) { set(&env, v); vehicle.operatingEnvelopeOverride = env } }
            ))
            .font(HUDTheme.monoFont(15, weight: .semibold)).foregroundStyle(color).textFieldStyle(.plain)
        }
    }

    private func envOptField(_ label: String, get: @escaping (OperatingEnvelope) -> Double?,
                             set: @escaping (inout OperatingEnvelope, Double?) -> Void, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(HUDTheme.monoFont(9)).foregroundStyle(HUDTheme.textSecondary)
            TextField("—", text: Binding(
                get: { get(vehicle.operatingEnvelope).map { String(format: "%g", $0) } ?? "" },
                set: { var env = vehicle.operatingEnvelope; set(&env, Double($0)); vehicle.operatingEnvelopeOverride = env }
            ))
            .font(HUDTheme.monoFont(15, weight: .semibold)).foregroundStyle(color).textFieldStyle(.plain)
        }
    }

    private func bandField(_ ph: String, _ i: Int, _ kp: WritableKeyPath<BoostBand, Int>) -> some View {
        TextField(ph, text: Binding(
            get: { String(vehicle.operatingEnvelope.expectedBoostByRPM[i][keyPath: kp]) },
            set: { newValue in updateBand(i) { if let v = Int(newValue) { $0[keyPath: kp] = v } } }
        ))
        .frame(width: 52).textFieldStyle(.roundedBorder)
    }

    private func bandPsiField(_ ph: String, _ i: Int, _ kp: WritableKeyPath<BoostBand, Double>) -> some View {
        TextField(ph, text: Binding(
            get: { String(format: "%g", vehicle.operatingEnvelope.expectedBoostByRPM[i][keyPath: kp]) },
            set: { newValue in updateBand(i) { if let v = Double(newValue) { $0[keyPath: kp] = v } } }
        ))
        .frame(width: 48).textFieldStyle(.roundedBorder)
    }

    private func updateBand(_ i: Int, _ mutate: (inout BoostBand) -> Void) {
        var env = vehicle.operatingEnvelope
        guard env.expectedBoostByRPM.indices.contains(i) else { return }
        mutate(&env.expectedBoostByRPM[i])
        vehicle.operatingEnvelopeOverride = env
    }

    private func removeBand(_ i: Int) {
        var env = vehicle.operatingEnvelope
        guard env.expectedBoostByRPM.indices.contains(i) else { return }
        env.expectedBoostByRPM.remove(at: i)
        vehicle.operatingEnvelopeOverride = env
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
