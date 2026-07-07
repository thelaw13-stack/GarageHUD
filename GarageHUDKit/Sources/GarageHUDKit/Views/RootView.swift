import SwiftUI

public struct RootView: View {
    @StateObject private var store = GarageStore()
    @StateObject private var purchases = PurchaseManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedVehicleID: UUID?
    @State private var showingAddVehicle = false
    @State private var showingUpgrade = false
    @State private var pendingSlot = 1

    public init() {}

    private var maxSlots: Int { purchases.isEightBayUnlocked ? 8 : 4 }

    public var body: some View {
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
        .environmentObject(store)
        .background(HUDTheme.background)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showingAddVehicle) {
            AddVehicleView(garageSlot: pendingSlot) { store.addVehicle($0) }
        }
        .sheet(isPresented: $showingUpgrade) {
            UpgradeView(purchases: purchases)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.syncNow() }
        }
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
