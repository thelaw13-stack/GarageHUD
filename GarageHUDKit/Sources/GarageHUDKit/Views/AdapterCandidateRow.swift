import SwiftUI

/// One tappable row in the scan-first pairing picker. A reachable adapter invites a tap to validate;
/// a dead-end MFi/Classic adapter (the OBDLink MX+) is shown, greyed, with the reason it can't be
/// opened — so the owner isn't lured into a connection that can never complete.
struct AdapterCandidateRow: View {
    let candidate: OBDAdapterCandidate
    let selected: Bool
    let enabled: Bool
    let onTap: () -> Void

    var body: some View {
        let reachable = candidate.isReachableOverBLE
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: !reachable ? "lock.slash"
                        : selected ? "checkmark.circle.fill" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(!reachable ? HUDTheme.textTertiary
                                     : selected ? HUDTheme.green : HUDTheme.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.name)
                        .font(HUDTheme.body(.semibold))
                        .foregroundStyle(reachable ? HUDTheme.textPrimary : HUDTheme.textSecondary)
                    if let reason = candidate.unreachableReason {
                        Text(reason)
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.amber)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("RSSI \(candidate.rssi)\(candidate.advertisedServiceUUIDs.isEmpty ? "" : " · " + candidate.advertisedServiceUUIDs.joined(separator: ", "))")
                            .font(HUDTheme.label())
                            .foregroundStyle(HUDTheme.textSecondary)
                    }
                }
                Spacer(minLength: 0)
                if reachable {
                    Image(systemName: "arrow.right.circle").foregroundStyle(HUDTheme.textSecondary)
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).fill(HUDTheme.panelBackground))
            .overlay(RoundedRectangle(cornerRadius: HUDTheme.cornerRadius).strokeBorder(HUDTheme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!reachable || !enabled)
    }
}
