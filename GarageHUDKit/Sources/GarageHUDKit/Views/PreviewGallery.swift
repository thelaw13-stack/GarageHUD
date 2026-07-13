#if DEBUG
import SwiftUI

/// Sample states used as the visual-regression reference for the refinement pass. Update these
/// when intentionally changing a screen; diff them before accepting future UI changes.
enum PreviewVehicles {
    private static func daysAgo(_ n: Int) -> Date { Calendar.current.date(byAdding: .day, value: -n, to: .now)! }

    /// A coherent, well-documented build.
    static var normal: Vehicle {
        var v = Vehicle(make: "Honda", model: "S2000", year: 2006, trim: "AP2", nickname: "S2K",
                        garageSlot: 1, factoryHorsepower: 237, factoryTorque: 162, factoryWeightLbs: 2855)
        v.drivetrain = .rwd
        v.documentedTotalInvestment = 24_500
        v.parts = [
            Part(name: "Supercharger", category: .forcedInduction, status: .installed, installDate: daysAgo(300), cost: 5760),
            Part(name: "ID1340 injectors", category: .fueling, status: .installed, installDate: daysAgo(300), cost: 945),
            Part(name: "Koyo radiator", category: .cooling, status: .installed, installDate: daysAgo(300)),
            Part(name: "CP pistons", category: .engine, status: .installed, installDate: daysAgo(360), cost: 859),
            Part(name: "SoS clutch", category: .drivetrain, status: .installed, installDate: daysAgo(300), cost: 908),
        ]
        v.performanceRecords = [PerformanceRecord(date: daysAgo(120), type: .dyno, wheelHorsepower: 477, wheelTorque: 317)]
        v.buildEvents = [BuildEvent(date: daysAgo(120), title: "Dyno tune — 477 whp")]
        return v
    }

    /// A sparse, barely-documented record.
    static var incomplete: Vehicle {
        var v = Vehicle(make: "Mazda", model: "MX-5", year: 2016, nickname: "Miata", garageSlot: 2, factoryHorsepower: 155)
        v.drivetrain = .rwd
        v.parts = [Part(name: "Exhaust", category: .exhaust, status: .installed)]
        return v
    }

    /// Out of service mid-rebuild, with a checklist and flagged parts.
    static var outOfService: Vehicle {
        var v = normal
        v.nickname = "S2K"
        v.serviceStatus = ServiceStatus(isInService: true, reason: "Engine teardown — internals under inspection",
                                        since: daysAgo(40),
                                        checklist: [ServiceTask(title: "Inspect bottom end", isDone: true),
                                                    ServiceTask(title: "Replace rod bearings"),
                                                    ServiceTask(title: "Reassemble & torque")])
        v.parts.append(Part(name: "King XP rod bearings", category: .engine, status: .installed, flaggedForRebuild: true))
        return v
    }

    /// Several unresolved supporting-system gaps → multiple Steward observations.
    static var multiObservation: Vehicle {
        var v = Vehicle(make: "Subaru", model: "WRX STI", year: 2015, nickname: "The Rex", garageSlot: 3, factoryHorsepower: 305)
        v.drivetrain = .awd
        v.parts = [Part(name: "Big turbo", category: .forcedInduction, status: .installed)]
        v.confirmedStockSystems = [.fueling, .cooling, .brakes]   // confirmed-stock while boosted → strong cautions
        v.performanceRecords = [PerformanceRecord(date: daysAgo(300), type: .dyno, wheelHorsepower: 420)]
        v.buildEvents = [BuildEvent(date: daysAgo(300), title: "Last touched")]
        return v
    }

    /// Long name + long checklist items — layout stress.
    static var longNames: Vehicle {
        var v = outOfService
        v.nickname = "Project Overkill — Track Weapon Build No. 2"
        v.serviceStatus.checklist = [
            ServiceTask(title: "Replace the King XP main and rod bearings and re-measure all clearances"),
            ServiceTask(title: "Reinstall the ScienceOfSpeed supercharger and complete the fuel-system reassembly"),
        ]
        return v
    }
}

@MainActor private func previewStore(_ vehicles: [Vehicle]) -> GarageStore {
    let s = GarageStore(syncEnabled: false)
    s.vehicles = vehicles
    return s
}

@MainActor private func overview(_ vehicles: [Vehicle], maxSlots: Int = 4, upgrade: Bool = false) -> some View {
    GarageOverviewView(selectedVehicleID: .constant(nil), maxSlots: maxSlots, canUpgrade: upgrade,
                       onAddVehicle: { _ in }, onUpgrade: {})
        .environmentObject(previewStore(vehicles))
        .preferredColorScheme(.dark)
}

#Preview("Garage · empty") { overview([]) }
#Preview("Garage · healthy fleet") { overview([PreviewVehicles.normal]) }
#Preview("Garage · mixed attention") { overview([PreviewVehicles.outOfService, PreviewVehicles.multiObservation]) }
#Preview("Garage · max bays") { overview([PreviewVehicles.normal, PreviewVehicles.incomplete,
                                          PreviewVehicles.multiObservation, PreviewVehicles.outOfService], maxSlots: 4) }

#Preview("Dashboard · normal") { VehicleDashboardView(vehicle: .constant(PreviewVehicles.normal)).preferredColorScheme(.dark) }
#Preview("Dashboard · incomplete") { VehicleDashboardView(vehicle: .constant(PreviewVehicles.incomplete)).preferredColorScheme(.dark) }
#Preview("Dashboard · out of service") { VehicleDashboardView(vehicle: .constant(PreviewVehicles.outOfService)).preferredColorScheme(.dark) }
#Preview("Dashboard · many observations") { VehicleDashboardView(vehicle: .constant(PreviewVehicles.multiObservation)).preferredColorScheme(.dark) }
#Preview("Dashboard · long names") { VehicleDashboardView(vehicle: .constant(PreviewVehicles.longNames)).preferredColorScheme(.dark) }

// Live telemetry states, as frames feeding the Steward's live read.
private func liveFrame(coolant: Double?, boost: Double?, throttle: Double?, source: MeasurementSource, ageSeconds: Double, state: OBDConnectionState) -> LiveTelemetryFrame {
    func m(_ v: Double?) -> TimedMeasurement<Double>? { v.map { TimedMeasurement($0, source: source, at: Date().addingTimeInterval(-ageSeconds)) } }
    return LiveTelemetryFrame(coolantTempF: m(coolant), boostPsi: m(boost), throttlePercent: m(throttle),
                              connectionState: state, capturedAt: Date())
}

@MainActor private func liveObservations(_ frame: LiveTelemetryFrame) -> some View {
    let obs = Steward.observe(frame: frame, for: PreviewVehicles.normal)
    return ScrollView {
        VStack(alignment: .leading, spacing: HUDTheme.space3) {
            Text("STEWARD · LIVE (\(String(describing: frame.connectionState)))")
                .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textSecondary)
            if obs.isEmpty { Text("No fresh, actionable values.").font(HUDTheme.body()).foregroundStyle(HUDTheme.textSecondary) }
            ForEach(obs) { StewardObservationRow($0) }
        }.padding(HUDTheme.space4)
    }
    .background(HUDTheme.background).preferredColorScheme(.dark)
}

#Preview("Live · measured") { liveObservations(liveFrame(coolant: 240, boost: 20, throttle: 90, source: .obdAdapter, ageSeconds: 0, state: .polling)) }
#Preview("Live · estimated") { liveObservations(liveFrame(coolant: 240, boost: 20, throttle: 90, source: .simulated, ageSeconds: 0, state: .polling)) }
#Preview("Live · stale") { liveObservations(liveFrame(coolant: 240, boost: 20, throttle: 90, source: .obdAdapter, ageSeconds: 5, state: .polling)) }
#Preview("Live · partial") { liveObservations(liveFrame(coolant: 240, boost: nil, throttle: nil, source: .obdAdapter, ageSeconds: 0, state: .polling)) }
#Preview("Live · disconnected") { liveObservations(liveFrame(coolant: nil, boost: nil, throttle: nil, source: .obdAdapter, ageSeconds: 0, state: .disconnected)) }
#endif
