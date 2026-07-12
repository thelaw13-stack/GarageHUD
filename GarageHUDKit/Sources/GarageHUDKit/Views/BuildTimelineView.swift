import SwiftUI

struct BuildTimelineView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAdd = false
    @State private var editingEvent: BuildEvent?
    /// Milestones = hand-logged build events only. Full history = the whole spine
    /// (part installs/removals, dyno pulls, notes) merged in date order.
    @State private var showFullHistory = false

    private var events: [BuildEvent] {
        vehicle.buildEvents.sorted { $0.date > $1.date }
    }

    private var spine: [TimelineEntry] { vehicle.timeline }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(showFullHistory ? "FULL HISTORY" : "BUILD PROGRESSION")
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(2)
                Spacer()
                Picker("", selection: $showFullHistory) {
                    Text("Milestones").tag(false)
                    Text("Full history").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Button {
                    showingAdd = true
                } label: {
                    Label("Log Event", systemImage: "plus")
                }
                .buttonStyle(HUDButtonStyle())
            }
            .padding()

            if showFullHistory {
                fullHistory
            } else {
                milestones
            }
        }
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAdd) {
            AddEditBuildEventView(vehicle: $vehicle, eventID: nil)
        }
        .sheet(item: $editingEvent) { event in
            AddEditBuildEventView(vehicle: $vehicle, eventID: event.id)
        }
    }

    @ViewBuilder
    private var milestones: some View {
        if events.isEmpty {
            Spacer()
            Text("No build events yet — log your first mod or milestone.")
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                        TimelineRow(event: event, isLast: index == events.count - 1)
                            .contentShape(Rectangle())
                            .onTapGesture { editingEvent = event }
                    }
                }
                .padding()
            }
        }
    }

    @ViewBuilder
    private var fullHistory: some View {
        if spine.isEmpty {
            Spacer()
            Text("Nothing dated yet — install dates, dyno pulls, and events all land here.")
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(spine.enumerated()), id: \.element.id) { index, entry in
                        SpineRow(entry: entry, isLast: index == spine.count - 1)
                    }
                }
                .padding()
            }
        }
    }
}

/// A single entry in the unified history spine, color/icon-coded by kind.
private struct SpineRow: View {
    var entry: TimelineEntry
    var isLast: Bool

    private var accent: Color {
        switch entry.kind {
        case .partInstalled: return HUDTheme.cyan
        case .partRemoved: return HUDTheme.textSecondary
        case .performance: return HUDTheme.amber
        case .buildEvent: return HUDTheme.green
        case .note: return HUDTheme.textSecondary
        }
    }

    private var icon: String {
        switch entry.kind {
        case .partInstalled: return "wrench.and.screwdriver.fill"
        case .partRemoved: return "minus.circle"
        case .performance: return "speedometer"
        case .buildEvent: return "flag.fill"
        case .note: return "note.text"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(accent)
                    .frame(width: 16, height: 16)
                if !isLast {
                    Rectangle().fill(accent.opacity(0.22)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.title)
                        .font(HUDTheme.monoFont(13, weight: .semibold))
                        .foregroundStyle(HUDTheme.textPrimary)
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                        .font(HUDTheme.monoFont(10))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(HUDTheme.monoFont(11))
                        .foregroundStyle(HUDTheme.textSecondary)
                        .lineLimit(2)
                }
            }
            .padding(.bottom, 18)
        }
    }
}

private struct TimelineRow: View {
    var event: BuildEvent
    var isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle().fill(HUDTheme.cyan).frame(width: 10, height: 10).hudGlow(HUDTheme.cyan, radius: 3)
                if !isLast {
                    Rectangle().fill(HUDTheme.cyan.opacity(0.25)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(event.title)
                        .font(HUDTheme.monoFont(13, weight: .semibold))
                        .foregroundStyle(HUDTheme.textPrimary)
                    Spacer()
                    Text(event.date.formatted(date: .abbreviated, time: .omitted))
                        .font(HUDTheme.monoFont(10))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                if !event.eventDescription.isEmpty {
                    Text(event.eventDescription)
                        .font(HUDTheme.monoFont(11))
                        .foregroundStyle(HUDTheme.textSecondary)
                }
                if let mileage = event.mileage {
                    Text("\(mileage) mi")
                        .font(HUDTheme.monoFont(10))
                        .foregroundStyle(HUDTheme.amber)
                }
                if !event.photos.isEmpty {
                    PhotoThumbnailStrip(photos: event.photos, onAdd: nil, onDelete: nil)
                        .frame(height: 70)
                }
            }
            .padding(.bottom, 20)
        }
    }
}
