import SwiftUI

struct VehicleDetailView: View {
    @Binding var vehicle: Vehicle
    var onBackToGarage: () -> Void
    var onDelete: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: DetailTab = .dashboard

    enum DetailTab: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard"
        case parts = "Parts"
        case timeline = "Timeline"
        case performance = "Performance"
        case tuner = "Tuner"
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
            case .tuner: "slider.horizontal.3"
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
            Divider().overlay(HUDTheme.hairline)
            tabContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(vehicle.id)
        .background(HUDTheme.background)
    }

    // A horizontal scrolling strip shows every section equally on every platform —
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
                                    .font(HUDTheme.label(.semibold))
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
                                    .strokeBorder(selectedTab == tab ? Color.clear : HUDTheme.hairline, lineWidth: 1)
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
                Label(horizontalSizeClass == .compact ? "Garage" : "All Vehicles", systemImage: "chevron.left")
                    .font(HUDTheme.label(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(HUDTheme.textSecondary)

            Divider().frame(height: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(vehicle.displayName.uppercased())
                    .font(HUDTheme.body(.semibold))
                    .foregroundStyle(HUDTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                if horizontalSizeClass != .compact {
                    Text(vehicle.subtitle)
                        .font(HUDTheme.label())
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            .layoutPriority(1)
            Spacer()

            // The car's shareable documents, reachable from every tab — not buried at the bottom
            // of Specs. Share arrow = human-readable sheet (the W-006 icon vocabulary).
            Menu {
                ShareLink(item: SharableBiographySheet(vehicle: vehicle),
                          preview: SharePreview("\(vehicle.displayName) biography")) {
                    Label("Vehicle biography (PDF)", systemImage: "book")
                }
                ShareLink(item: BuildSheetExporter.file(for: vehicle),
                          preview: SharePreview("\(vehicle.displayName) build sheet")) {
                    Label("Build sheet (text)", systemImage: "doc.plaintext")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
                    .foregroundStyle(HUDTheme.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Share this car's documents")

            if vehicle.serviceStatus.isInService {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(HUDTheme.amber)
                    .accessibilityLabel("In service")
            }
            Text("BAY \(vehicle.garageSlot)")
                .font(HUDTheme.label(.semibold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1)
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(HUDTheme.panelBackground)
        .overlay(Rectangle().frame(height: 1).foregroundStyle(HUDTheme.hairline), alignment: .bottom)
    }

    @ViewBuilder
    private func tabContent(for tab: DetailTab) -> some View {
        switch tab {
        case .dashboard: VehicleDashboardView(vehicle: $vehicle, onNavigate: { tab in
            withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
        })
        case .parts: PartsInventoryView(vehicle: $vehicle)
        case .timeline: BuildTimelineView(vehicle: $vehicle)
        case .performance: PerformanceView(vehicle: $vehicle)
        case .tuner: TunerView(vehicle: $vehicle, onNavigate: { tab in
            withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
        })
        case .live: LiveSessionView(vehicle: $vehicle)
        case .gallery: GalleryView(vehicle: $vehicle)
        case .notes: NotesView(vehicle: $vehicle)
        case .specs: SpecSheetView(vehicle: $vehicle, onDelete: onDelete)
        }
    }
}
