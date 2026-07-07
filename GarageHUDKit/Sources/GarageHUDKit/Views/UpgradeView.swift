import SwiftUI

struct UpgradeView: View {
    @ObservedObject var purchases: PurchaseManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 20)

            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 44))
                .foregroundStyle(HUDTheme.cyan)
                .hudGlow(HUDTheme.cyan, radius: 8)

            Text("EXPAND TO 8 BAYS")
                .font(HUDTheme.monoFont(20, weight: .bold))
                .foregroundStyle(HUDTheme.cyan)
                .tracking(1.5)

            Text("Your garage holds 4 vehicles free. Unlock a one-time upgrade to track up to 8 — a permanent purchase tied to your Apple ID, restorable on all your devices.")
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                ForEach(["4 extra garage bays", "Syncs across Mac & iPhone", "One-time purchase, no subscription"], id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(HUDTheme.green)
                        Text(line).font(HUDTheme.monoFont(12)).foregroundStyle(HUDTheme.textPrimary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 10)

            if purchases.isEightBayUnlocked {
                Label("Unlocked — you have 8 bays", systemImage: "checkmark.seal.fill")
                    .font(HUDTheme.monoFont(13, weight: .semibold))
                    .foregroundStyle(HUDTheme.green)
            } else if let product = purchases.product {
                Button {
                    Task { if await purchases.purchase() { dismiss() } }
                } label: {
                    HStack {
                        if purchases.purchaseInFlight { ProgressView().tint(HUDTheme.background) }
                        Text("Unlock 8 Bays — \(product.displayPrice)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(HUDButtonStyle())
                .disabled(purchases.purchaseInFlight)
                .padding(.horizontal, 40)

                Button("Restore Purchase") { Task { await purchases.restore() } }
                    .font(HUDTheme.monoFont(11))
                    .foregroundStyle(HUDTheme.textSecondary)
            } else {
                Text("Upgrade not available yet.\n(Requires the in-app purchase to be set up in App Store Connect.)")
                    .font(HUDTheme.monoFont(10))
                    .foregroundStyle(HUDTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Restore Purchase") { Task { await purchases.restore() } }
                    .font(HUDTheme.monoFont(11))
                    .foregroundStyle(HUDTheme.textSecondary)
            }

            Button("Not Now") { dismiss() }
                .font(HUDTheme.monoFont(12))
                .foregroundStyle(HUDTheme.textSecondary)
                .padding(.top, 4)

            Spacer(minLength: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDTheme.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
