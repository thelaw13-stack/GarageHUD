import SwiftUI

struct TunerView: View {
    @Binding var vehicle: Vehicle

    private var readiness: TuneReadiness { Steward.tuneReadiness(vehicle) }
    private var bands: [BoostBand] { vehicle.operatingEnvelope.expectedBoostByRPM }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HUDTheme.space4) {
                statusPanel
                readinessPanel
                tuneEnvelopePanel
            }
            .padding(HUDTheme.space4)
        }
        .background(HUDTheme.background)
    }

    private var statusPanel: some View {
        HUDPanel {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: HUDTheme.space4) {
                    statusIdentity
                    Spacer(minLength: HUDTheme.space3)
                    evidenceCounts
                }
                VStack(alignment: .leading, spacing: HUDTheme.space3) {
                    statusIdentity
                    evidenceCounts
                }
            }
        }
    }

    private var statusIdentity: some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(statusColor.opacity(0.12)))
            VStack(alignment: .leading, spacing: HUDTheme.space1) {
                Text("TUNE \(readiness.state.label.uppercased())")
                    .font(HUDTheme.section(.bold))
                    .foregroundStyle(statusColor)
                Text(readiness.headline)
                    .font(HUDTheme.body(.medium))
                    .foregroundStyle(HUDTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(readiness.confidence.label.uppercased())
                    .font(HUDTheme.label(.semibold))
                    .foregroundStyle(HUDTheme.textTertiary)
                    .tracking(1)
            }
        }
    }

    private var evidenceCounts: some View {
        HStack(spacing: HUDTheme.space4) {
            count(readiness.readyCount, "CLEAR", HUDTheme.green)
            count(readiness.verifyCount, "VERIFY", HUDTheme.amber)
            count(readiness.holdCount, "HOLD", HUDTheme.danger)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)").font(HUDTheme.section(.bold)).foregroundStyle(color)
            Text(label).font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary).tracking(1)
        }
    }

    private var readinessPanel: some View {
        HUDPanel(title: "Pre-Pull Logic") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(readiness.checks.enumerated()), id: \.element.id) { index, check in
                    checkRow(check)
                    if index < readiness.checks.count - 1 {
                        Divider().overlay(HUDTheme.hairline).padding(.leading, 34)
                    }
                }
            }
        }
    }

    private func checkRow(_ check: TuneReadiness.Check) -> some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            Image(systemName: icon(for: check.state))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color(for: check.state))
                .frame(width: 18, height: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(check.title).font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                    Spacer(minLength: HUDTheme.space2)
                    Text(check.state.label.uppercased())
                        .font(HUDTheme.label(.semibold)).foregroundStyle(color(for: check.state)).tracking(1)
                }
                Text(check.detail)
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, HUDTheme.space2)
        .accessibilityElement(children: .combine)
    }

    private var tuneEnvelopePanel: some View {
        HUDPanel(title: "Boost Target Map") {
            VStack(alignment: .leading, spacing: HUDTheme.space3) {
                Text("Live compares measured boost with this RPM envelope. These values document the intended tune; they do not command the ECU.")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: HUDTheme.space3)], spacing: HUDTheme.space3) {
                    optionalField("BOOST CAUTION", keyPath: \.boostCautionPsi, color: HUDTheme.amber)
                    optionalField("HARD CEILING", keyPath: \.maxSustainedBoostPsi, color: HUDTheme.danger)
                }

                if !bands.isEmpty { bandPlot }

                HStack {
                    Text("RPM BANDS").font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.cyan).tracking(1)
                    Spacer()
                    Button { addBand() } label: { Label("Add Band", systemImage: "plus") }
                        .buttonStyle(.compactAction)
                }

                if bands.isEmpty {
                    Text("Add the first RPM range to make Live judge boost against the intended shape of the tune.")
                        .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                } else {
                    ForEach(bands.indices, id: \.self) { index in
                        bandEditor(index)
                    }
                }
            }
        }
    }

    private var bandPlot: some View {
        VStack(alignment: .leading, spacing: HUDTheme.space2) {
            ForEach(Array(bands.enumerated()), id: \.offset) { index, band in
                VStack(alignment: .leading, spacing: HUDTheme.space1) {
                    HStack {
                        Text("\(band.rpmLow)-\(band.rpmHigh) RPM")
                        Spacer()
                        Text("\(format(band.expectedLowPsi))-\(format(band.expectedHighPsi)) PSI")
                    }
                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary)
                    GeometryReader { proxy in
                        let maxPSI = max(plotMaximum, 1)
                        let start = max(0, band.expectedLowPsi / maxPSI) * proxy.size.width
                        let width = max(3, (band.expectedHighPsi - band.expectedLowPsi) / maxPSI * proxy.size.width)
                        ZStack(alignment: .leading) {
                            Capsule().fill(HUDTheme.hairline).frame(height: 5)
                            Capsule().fill(index.isMultiple(of: 2) ? HUDTheme.cyan : HUDTheme.green)
                                .frame(width: width, height: 5).offset(x: start)
                        }
                    }
                    .frame(height: 5)
                }
            }
        }
        .padding(.vertical, HUDTheme.space2)
    }

    private var plotMaximum: Double {
        max(vehicle.operatingEnvelope.maxSustainedBoostPsi ?? 0,
            bands.map(\.expectedHighPsi).max() ?? 0) * 1.08
    }

    private func bandEditor(_ index: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: HUDTheme.space2) {
                intField("LOW RPM", index, \.rpmLow)
                intField("HIGH RPM", index, \.rpmHigh)
                doubleField("LOW PSI", index, \.expectedLowPsi)
                doubleField("HIGH PSI", index, \.expectedHighPsi)
                removeButton(index)
            }
            VStack(alignment: .leading, spacing: HUDTheme.space2) {
                HStack(spacing: HUDTheme.space2) {
                    intField("LOW RPM", index, \.rpmLow)
                    intField("HIGH RPM", index, \.rpmHigh)
                }
                HStack(spacing: HUDTheme.space2) {
                    doubleField("LOW PSI", index, \.expectedLowPsi)
                    doubleField("HIGH PSI", index, \.expectedHighPsi)
                    removeButton(index)
                }
            }
        }
        .padding(.vertical, HUDTheme.space2)
    }

    private func intField(_ label: String, _ index: Int, _ keyPath: WritableKeyPath<BoostBand, Int>) -> some View {
        labeledField(label, text: Binding(
            get: { String(bands[index][keyPath: keyPath]) },
            set: { value in updateBand(index) { if let number = Int(value) { $0[keyPath: keyPath] = number } } }
        ))
    }

    private func doubleField(_ label: String, _ index: Int, _ keyPath: WritableKeyPath<BoostBand, Double>) -> some View {
        labeledField(label, text: Binding(
            get: { format(bands[index][keyPath: keyPath]) },
            set: { value in updateBand(index) { if let number = Double(value) { $0[keyPath: keyPath] = number } } }
        ))
    }

    private func labeledField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            TextField("0", text: text)
                .font(HUDTheme.body(.semibold)).foregroundStyle(HUDTheme.textPrimary)
                .textFieldStyle(.plain)
                .padding(.horizontal, HUDTheme.space2).frame(minHeight: 34)
                .background(RoundedRectangle(cornerRadius: 6).fill(HUDTheme.elevatedSurface))
        }
        .frame(maxWidth: .infinity)
    }

    private func optionalField(_ label: String, keyPath: WritableKeyPath<OperatingEnvelope, Double?>,
                               color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            HStack(alignment: .firstTextBaseline, spacing: HUDTheme.space1) {
                TextField("Not set", text: Binding(
                    get: { vehicle.operatingEnvelope[keyPath: keyPath].map(format) ?? "" },
                    set: { value in
                        var envelope = vehicle.operatingEnvelope
                        envelope[keyPath: keyPath] = Double(value)
                        vehicle.operatingEnvelopeOverride = envelope
                    }
                ))
                .font(HUDTheme.section(.bold)).foregroundStyle(color).textFieldStyle(.plain)
                Text("PSI").font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
            }
        }
    }

    private func addBand() {
        var envelope = vehicle.operatingEnvelope
        let previous = envelope.expectedBoostByRPM.max { $0.rpmHigh < $1.rpmHigh }
        let low = previous.map { $0.rpmHigh + 1 } ?? 3000
        let high = low + 1999
        let lowPSI = previous?.expectedLowPsi ?? 10
        let highPSI = previous?.expectedHighPsi ?? 16
        envelope.expectedBoostByRPM.append(BoostBand(rpmLow: low, rpmHigh: high,
                                                     expectedLowPsi: lowPSI, expectedHighPsi: highPSI))
        envelope.expectedBoostByRPM.sort { $0.rpmLow < $1.rpmLow }
        vehicle.operatingEnvelopeOverride = envelope
    }

    private func updateBand(_ index: Int, mutate: (inout BoostBand) -> Void) {
        var envelope = vehicle.operatingEnvelope
        guard envelope.expectedBoostByRPM.indices.contains(index) else { return }
        mutate(&envelope.expectedBoostByRPM[index])
        vehicle.operatingEnvelopeOverride = envelope
    }

    private func removeButton(_ index: Int) -> some View {
        Button { removeBand(index) } label: {
            Image(systemName: "trash").frame(width: 34, height: 34)
        }
        .buttonStyle(.plain).foregroundStyle(HUDTheme.danger)
        .accessibilityLabel("Remove RPM band")
    }

    private func removeBand(_ index: Int) {
        var envelope = vehicle.operatingEnvelope
        guard envelope.expectedBoostByRPM.indices.contains(index) else { return }
        envelope.expectedBoostByRPM.remove(at: index)
        vehicle.operatingEnvelopeOverride = envelope
    }

    private var statusColor: Color { color(for: readiness.state) }
    private var statusIcon: String { icon(for: readiness.state) }

    private func color(for state: TuneReadiness.State) -> Color {
        switch state {
        case .ready: return HUDTheme.green
        case .verify: return HUDTheme.amber
        case .hold: return HUDTheme.danger
        }
    }

    private func icon(for state: TuneReadiness.State) -> String {
        switch state {
        case .ready: return "checkmark.circle.fill"
        case .verify: return "questionmark.circle.fill"
        case .hold: return "exclamationmark.octagon.fill"
        }
    }

    private func format(_ value: Double) -> String { String(format: "%g", value) }
}
