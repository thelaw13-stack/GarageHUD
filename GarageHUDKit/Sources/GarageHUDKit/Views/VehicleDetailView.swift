import SwiftUI

struct VehicleDetailView: View {
    @Binding var vehicle: Vehicle
    var onBackToGarage: () -> Void
    var onDelete: () -> Void
    @State private var selectedTab: DetailTab = .dashboard

    enum DetailTab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case parts = "Parts"
        case timeline = "Timeline"
        case performance = "Performance"
        case live = "Live"
        case gallery = "Gallery"
        case notes = "Notes"
        case specs = "Specs"

        var id: String { rawValue }

        /// Live telemetry is a Bluetooth OBD-II feature — iPhone only (not shown on Mac).
        static var available: [DetailTab] {
            #if os(macOS)
            allCases.filter { $0 != .live }
            #else
            allCases
            #endif
        }

        var systemImage: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.67percent"
            case .parts: "wrench.and.screwdriver"
            case .timeline: "clock.arrow.circlepath"
            case .performance: "speedometer"
            case .live: "dot.radiowaves.left.and.right"
            case .gallery: "photo.on.rectangle"
            case .notes: "note.text"
            case .specs: "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            vehicleBanner
            tabStrip
            Divider().overlay(HUDTheme.cyan.opacity(0.2))
            tabContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(vehicle.id)
        .background(HUDTheme.background)
    }

    // A horizontal scrolling strip shows all 8 sections equally on every platform —
    // iOS caps a native TabView at 5 items and hides the rest under "More".
    private var tabStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DetailTab.available) { tab in
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 12))
                                Text(tab.rawValue.uppercased())
                                    .font(HUDTheme.monoFont(10, weight: .semibold))
                                    .tracking(1)
                            }
                            .foregroundStyle(selectedTab == tab ? HUDTheme.background : HUDTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedTab == tab ? HUDTheme.cyan : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(HUDTheme.cyan.opacity(selectedTab == tab ? 0 : 0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .id(tab)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation { proxy.scrollTo(newTab, anchor: .center) }
            }
        }
        .background(HUDTheme.panelBackground.opacity(0.5))
    }

    private var vehicleBanner: some View {
        HStack(spacing: 10) {
            Button(action: onBackToGarage) {
                Label("All Vehicles", systemImage: "chevron.left")
                    .font(HUDTheme.monoFont(10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HUDTheme.textSecondary)

            Divider().frame(height: 14)

            Circle().fill(HUDTheme.cyan).frame(width: 7, height: 7).hudGlow(HUDTheme.cyan, radius: 3)
            Text(vehicle.displayName.uppercased())
                .font(HUDTheme.monoFont(13, weight: .bold))
                .foregroundStyle(HUDTheme.cyan)
            Text(vehicle.subtitle)
                .font(HUDTheme.monoFont(11))
                .foregroundStyle(HUDTheme.textSecondary)
            Spacer()
            if vehicle.serviceStatus.isInService {
                Text("IN SERVICE")
                    .font(HUDTheme.monoFont(8, weight: .semibold))
                    .foregroundStyle(HUDTheme.amber)
                    .tracking(1)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .overlay(Capsule().strokeBorder(HUDTheme.amber.opacity(0.5), lineWidth: 1))
            }
            Text("BAY \(vehicle.garageSlot)")
                .font(HUDTheme.monoFont(9, weight: .semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HUDTheme.panelBackground)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HUDTheme.cyan.opacity(0.25)), alignment: .bottom)
    }

    @ViewBuilder
    private func tabContent(for tab: DetailTab) -> some View {
        switch tab {
        case .dashboard: VehicleDashboardView(vehicle: $vehicle)
        case .parts: PartsInventoryView(vehicle: $vehicle)
        case .timeline: BuildTimelineView(vehicle: $vehicle)
        case .performance: PerformanceView(vehicle: $vehicle)
        case .live: LiveSessionView(vehicle: $vehicle)
        case .gallery: GalleryView(vehicle: $vehicle)
        case .notes: NotesView(vehicle: $vehicle)
        case .specs: SpecSheetView(vehicle: $vehicle, onDelete: onDelete)
        }
    }
}
