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

            Text("EXPAND TO 8 BAYS")
                .font(HUDTheme.section(.bold))
                .foregroundStyle(HUDTheme.textSecondary)
                .tracking(1.5)

            Text("Your garage holds 4 vehicles free. Unlock a one-time upgrade to track up to 8 — a permanent purchase tied to your Apple ID, restorable on all your devices.")
                .font(HUDTheme.body())
                .foregroundStyle(HUDTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            VStack(spacing: 6) {
                ForEach(["4 extra garage bays", "Syncs across Mac & iPhone", "One-time purchase, no subscription"], id: \.self) { line in
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(HUDTheme.green)
                        Text(line).font(HUDTheme.body()).foregroundStyle(HUDTheme.textPrimary)
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer(minLength: 10)

            if purchases.isEightBayUnlocked {
                Label("Unlocked — you have 8 bays", systemImage: "checkmark.seal.fill")
                    .font(HUDTheme.body(.semibold))
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
                .buttonStyle(.primaryAction)
                .disabled(purchases.purchaseInFlight)
                .padding(.horizontal, 40)

                Button("Restore Purchase") { Task { await purchases.restore() } }
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
            } else {
                Text("Upgrade not available yet.\n(Requires the in-app purchase to be set up in App Store Connect.)")
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Restore Purchase") { Task { await purchases.restore() } }
                    .font(HUDTheme.label())
                    .foregroundStyle(HUDTheme.textSecondary)
            }

            Button("Not Now") { dismiss() }
                .font(HUDTheme.body())
                .foregroundStyle(HUDTheme.textSecondary)
                .padding(.top, 4)

            Spacer(minLength: 20)

            // TESTING ONLY — simulate the purchase so the 8-bay / 5th-vehicle state can be exercised
            // before the IAP is live. Remove before an App Store submission.
            Button(purchases.isEightBayUnlocked ? "Testing: lock back to 4 bays"
                                                 : "Testing: simulate purchase") {
                purchases.setUnlockedForTesting(!purchases.isEightBayUnlocked)
                if purchases.isEightBayUnlocked { dismiss() }
            }
            .font(HUDTheme.label())
            .foregroundStyle(HUDTheme.textTertiary)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HUDTheme.background.ignoresSafeArea())
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
