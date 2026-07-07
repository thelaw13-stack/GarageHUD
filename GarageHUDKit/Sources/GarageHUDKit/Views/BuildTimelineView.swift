import SwiftUI

struct BuildTimelineView: View {
    @Binding var vehicle: Vehicle
    @State private var showingAdd = false
    @State private var editingEvent: BuildEvent?

    private var events: [BuildEvent] {
        vehicle.buildEvents.sorted { $0.date > $1.date }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("BUILD PROGRESSION")
                    .font(HUDTheme.monoFont(11, weight: .semibold))
                    .foregroundStyle(HUDTheme.cyan)
                    .tracking(2)
                Spacer()
                Button {
                    showingAdd = true
                } label: {
                    Label("Log Event", systemImage: "plus")
                }
                .buttonStyle(HUDButtonStyle())
            }
            .padding()

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
        .background(HUDTheme.background)
        .sheet(isPresented: $showingAdd) {
            AddEditBuildEventView(vehicle: $vehicle, eventID: nil)
        }
        .sheet(item: $editingEvent) { event in
            AddEditBuildEventView(vehicle: $vehicle, eventID: event.id)
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
