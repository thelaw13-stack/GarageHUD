import Foundation
import StoreKit

/// Handles the one-time "8-Bay Garage" in-app purchase. Free tier = 4 bays;
/// buying the unlock (non-consumable) raises it to 8. Uses StoreKit 2.
@MainActor
public final class PurchaseManager: ObservableObject {
    public static let eightBaysProductID = "com.vanlaw.GarageHUD.eightbays"
    private static let unlockKey = "GHUD.eightBaysUnlocked"

    @Published public private(set) var isEightBayUnlocked: Bool
    @Published public private(set) var product: Product?
    @Published public private(set) var purchaseInFlight = false

    private var updatesTask: Task<Void, Never>?

    public init() {
        isEightBayUnlocked = Self.initialUnlockedState(
            storedUnlock: UserDefaults.standard.bool(forKey: Self.unlockKey),
            developmentForceUnlock: Self.developmentForceUnlock)
        updatesTask = listenForTransactions()
        Task { await refresh() }
    }

    deinit { updatesTask?.cancel() }

    public var priceText: String { product?.displayPrice ?? "" }

    public func refresh() async {
        product = try? await Product.products(for: [Self.eightBaysProductID]).first
        await updateEntitlement()
    }

    /// Returns true on a successful purchase.
    @discardableResult
    public func purchase() async -> Bool {
        guard let product else { return false }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result, case .verified(let transaction) = verification {
                await transaction.finish()
                setUnlocked(true)
                return true
            }
        } catch {}
        return false
    }

    public func restore() async {
        try? await AppStore.sync()
        await updateEntitlement()
    }

    private func updateEntitlement() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result,
               t.productID == Self.eightBaysProductID,
               t.revocationDate == nil {
                unlocked = true
            }
        }
        // Never downgrade a locally-remembered unlock just because entitlements haven't
        // loaded yet (e.g. offline); only upgrade to unlocked.
        if unlocked { setUnlocked(true) }
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.updateEntitlement()
                }
            }
        }
    }

    private func setUnlocked(_ value: Bool) {
        isEightBayUnlocked = value
        UserDefaults.standard.set(value, forKey: Self.unlockKey)
    }

    /// Debug builds keep the 8-bay state available for local development and review, while
    /// release builds start from the real stored entitlement/purchase state.
    nonisolated static var developmentForceUnlock: Bool { _isDebugAssertConfiguration() }

    nonisolated static func initialUnlockedState(storedUnlock: Bool, developmentForceUnlock: Bool) -> Bool {
        storedUnlock || developmentForceUnlock
    }

    #if DEBUG
    /// Grant/revoke the 8-bay unlock without a real purchase, so the paid state (bays 5-8,
    /// a 5th vehicle) can be exercised locally before the IAP is live in App Store Connect.
    public func setUnlockedForTesting(_ value: Bool) { setUnlocked(value) }
    #endif
}
