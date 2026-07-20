import SwiftUI

public struct RootView: View {
    @StateObject private var store = GarageStore()
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedVehicleID: UUID?
    @State private var compactPath: [UUID] = []
    @State private var showingAddVehicle = false
    @State private var showingUpgrade = false
    @State private var pendingSlot = 1

    public init() {}

    private var maxSlots: Int { purchases.isEightBayUnlocked ? 8 : 4 }

    public var body: some View {
        Group {
            if horizontalSizeClass == .compact {
                compactNavigation
            } else {
                splitNavigation
            }
        }
        .environmentObject(store)
        .background(HUDTheme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddVehicle) {
            AddVehicleView(garageSlot: pendingSlot) { store.addVehicle($0) }
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(purchases: purchases)
        }
        // W-068: iCloud's silent nudge arrives as a notification from the app delegate; turn it into
        // the same guarded pull used on foreground. Freshness stops depending on a relaunch.
        .onReceive(NotificationCenter.default.publisher(
            for: Notification.Name("GarageHUD.remoteChangeNoticed"))) { _ in
            store.remoteChangeNoticed()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.syncNow() }
            #if canImport(UserNotifications)
            MaintenanceNotifier.sync(for: store.vehicles)
            #endif
        }
        .onAppear {
            #if canImport(UserNotifications)
            MaintenanceNotifier.requestAuthorization()
            MaintenanceNotifier.sync(for: store.vehicles)
            #endif
        }
    }

    private var splitNavigation: some View {
        NavigationSplitView {
            GarageListView(
                selectedVehicleID: $selectedVehicleID,
                maxSlots: maxSlots,
                canUpgrade: !purchases.isEightBayUnlocked,
                onAddVehicle: { slot in
                    pendingSlot = slot
                    showingAddVehicle = true
                },
                onUpgrade: { showingUpgrade = true }
            )
            .navigationTitle("GARAGE")
        } detail: {
            if let id = selectedVehicleID, store.vehicles.contains(where: { $0.id == id }) {
                VehicleDetailView(
                    vehicle: binding(for: id),
                    onBackToGarage: { selectedVehicleID = nil },
                    onDelete: {
                        selectedVehicleID = nil
                        store.deleteVehicle(id: id)
                    }
                )
            } else {
                GarageOverviewView(
                    selectedVehicleID: $selectedVehicleID,
                    maxSlots: maxSlots,
                    canUpgrade: !purchases.isEightBayUnlocked,
                    onAddVehicle: { slot in
                        pendingSlot = slot
                        showingAddVehicle = true
                    },
                    onUpgrade: { showingUpgrade = true }
                )
            }
        }
    }

    private var compactNavigation: some View {
        NavigationStack(path: $compactPath) {
            garageOverview
                .navigationDestination(for: UUID.self) { id in
                    if store.vehicles.contains(where: { $0.id == id }) {
                        vehicleDetail(id: id, compact: true)
                    }
                }
        }
        .onChange(of: selectedVehicleID) { _, id in
            guard horizontalSizeClass == .compact else { return }
            if let id, compactPath.last != id {
                compactPath = [id]
            } else if id == nil, !compactPath.isEmpty {
                compactPath = []
            }
        }
        .onChange(of: compactPath) { _, path in
            let visibleID = path.last
            if selectedVehicleID != visibleID { selectedVehicleID = visibleID }
        }
    }

    private var garageOverview: some View {
        GarageOverviewView(
            selectedVehicleID: $selectedVehicleID,
            maxSlots: maxSlots,
            canUpgrade: !purchases.isEightBayUnlocked,
            onAddVehicle: { slot in
                pendingSlot = slot
                showingAddVehicle = true
            },
            onUpgrade: { showingUpgrade = true }
        )
    }

    private func vehicleDetail(id: UUID, compact: Bool) -> some View {
        VehicleDetailView(
            vehicle: binding(for: id),
            onBackToGarage: {
                selectedVehicleID = nil
                if compact { compactPath = [] }
            },
            onDelete: {
                selectedVehicleID = nil
                if compact { compactPath = [] }
                store.deleteVehicle(id: id)
            }
        )
    }

    /// A binding that resolves the vehicle by stable id every access, so it can't crash
    /// if the underlying array is reordered or shrinks (e.g. a sync pull) while a detail
    /// view holds it — unlike binding by array index.
    private func binding(for id: UUID) -> Binding<Vehicle> {
        Binding(
            get: { store.vehicles.first(where: { $0.id == id }) ?? Vehicle(make: "", model: "", year: 0, garageSlot: 0) },
            set: { newValue in
                if let i = store.vehicles.firstIndex(where: { $0.id == id }) {
                    store.vehicles[i] = newValue
                }
            }
        )
    }
}
