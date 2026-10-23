import Foundation
import StoreKit

/// What you've bought, read from StoreKit's verified transactions and cached for every Pinscape
/// process. The cache carries the subscription's expiry, so an extension running while the app
/// hasn't been opened never trusts Pro past the date it lapses.
enum Entitlements {
    static let monthlyID = "com.pinscape.pro.monthly"
    static let yearlyID = "com.pinscape.pro.yearly"
    static let stickerPackID = "com.pinscape.stickerpack"
    static let subscriptionIDs: Set<String> = [monthlyID, yearlyID]

    struct State: Equatable {
        var isPro: Bool
        var hasStickerPack: Bool
        var proExpiresAt: Date?
    }

    /// Reads current verified entitlements and updates the shared cache.
    @discardableResult
    static func refresh(now: Date = Date()) async -> State {
        var state = State(isPro: false, hasStickerPack: false, proExpiresAt: nil)
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if subscriptionIDs.contains(transaction.productID) {
                if let expiry = transaction.expirationDate {
                    guard expiry > now else { continue }
                    state.proExpiresAt = max(state.proExpiresAt ?? expiry, expiry)
                }
                state.isPro = true
            } else if transaction.productID == stickerPackID {
                state.hasStickerPack = true
            }
        }
        AppGroup.defaults.set(state.isPro, forKey: SharedKeys.isPro)
        AppGroup.defaults.set(state.hasStickerPack, forKey: SharedKeys.hasStickerPack)
        AppGroup.defaults.set(state.proExpiresAt, forKey: SharedKeys.proExpiresAt)
        return state
    }

    /// The cached answer, for code that can't wait on StoreKit.
    static var cachedIsPro: Bool {
        guard AppGroup.defaults.bool(forKey: SharedKeys.isPro) else { return false }
        if let expiry = AppGroup.defaults.object(forKey: SharedKeys.proExpiresAt) as? Date, expiry <= Date() {
            return false
        }
        return true
    }
}
