import SwiftUI

/// The discovery surface for preserved garage files. GarageHUD's data-safety story writes
/// conflict snapshots and unreadable-file backups to disk — but a safety file the owner can't
/// find is not safety. This view lists every preserved snapshot with what it contains, and
/// offers the three honest actions: export it, restore it (undoably — the current garage is
/// preserved first), or delete it.
struct RecoveryView: View {
    @ObservedObject var store: GarageStore
    @Environment(\.dismiss) private var dismiss

    @State private var confirmingRestore: GarageStore.RecoverySnapshot?
    @State private var restoreFailed = false

    var body: some View {
        NavigationStack {
            List {
                if store.recoverySnapshots.isEmpty {
                    Text("No preserved garage files.")
                        .foregroundStyle(HUDTheme.textSecondary)
                } else {
                    Section {
                        ForEach(store.recoverySnapshots) { snapshot in
                            row(snapshot)
                        }
                    } footer: {
                        Text("Restoring replaces the current garage with a snapshot's contents. The current garage is preserved first, so a restore can itself be restored from.")
                    }
                }
            }
            .navigationTitle("Recovery")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog(
                confirmTitle,
                isPresented: Binding(get: { confirmingRestore != nil },
                                     set: { if !$0 { confirmingRestore = nil } }),
                titleVisibility: .visible
            ) {
                Button("Restore this snapshot", role: .destructive) {
                    if let snapshot = confirmingRestore {
                        restoreFailed = !store.restore(from: snapshot)
                    }
                    confirmingRestore = nil
                }
                Button("Cancel", role: .cancel) { confirmingRestore = nil }
            }
            .alert("Could not restore", isPresented: $restoreFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("That file doesn't decode as a garage. It was left untouched — export it if you want to inspect the raw contents.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 380)
        #endif
    }

    private var confirmTitle: String {
        guard let s = confirmingRestore, let count = s.vehicleCount else { return "Restore?" }
        return "Replace the current garage (\(store.vehicles.count) car\(store.vehicles.count == 1 ? "" : "s")) with this snapshot (\(count) car\(count == 1 ? "" : "s"))?"
    }

    @ViewBuilder
    private func row(_ snapshot: GarageStore.RecoverySnapshot) -> some View {
        HStack(alignment: .top, spacing: HUDTheme.space3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(kindLabel(snapshot.kind))
                    .font(HUDTheme.label(.semibold)).foregroundStyle(HUDTheme.textPrimary).tracking(1)
                Text(snapshot.savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textSecondary)
                Text(snapshot.vehicleCount.map { "\($0) vehicle\($0 == 1 ? "" : "s")" } ?? "Unreadable — export to inspect")
                    .font(HUDTheme.label()).foregroundStyle(HUDTheme.textTertiary)
            }
            Spacer(minLength: 0)
            if let data = try? Data(contentsOf: snapshot.url) {
                ShareLink(item: GarageBackup(data: data, filename: snapshot.url.lastPathComponent),
                          preview: SharePreview("Preserved garage file")) {
                    Image(systemName: "archivebox")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Export preserved file")
            }
            if snapshot.vehicleCount != nil {
                Button("Restore") { confirmingRestore = snapshot }
                    .buttonStyle(.borderless)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { store.deleteRecoverySnapshot(snapshot) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func kindLabel(_ kind: GarageStore.RecoverySnapshot.Kind) -> String {
        switch kind {
        case .syncConflict: return "SYNC CONFLICT"
        case .preRestore: return "PRE-RESTORE COPY"
        case .unreadableFile: return "UNREADABLE FILE"
        }
    }
}
