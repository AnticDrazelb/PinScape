import Foundation
import Observation
import StoreKit

/// Pinscape Pro and the Sticker Pack, through StoreKit 2.
@MainActor
@Observable
final class ProStore {
    static let shared = ProStore()

    static let monthlyID = "com.pinscape.pro.monthly"
    static let yearlyID = "com.pinscape.pro.yearly"
    static let stickerPackID = "com.pinscape.stickerpack"
    static let subscriptionIDs: Set<String> = [monthlyID, yearlyID]

    private(set) var products: [Product] = []
    private(set) var isPro: Bool
    private(set) var hasStickerPack: Bool
    private(set) var hasLoadedProducts = false

    @ObservationIgnored private var updatesTask: Task<Void, Never>? = nil
    private init() {
        isPro = PinscapePlan.isPro
        hasStickerPack = AppGroup.defaults.bool(forKey: SharedKeys.hasStickerPack)
    }

    var monthly: Product? { products.first { $0.id == Self.monthlyID } }
    var yearly: Product? { products.first { $0.id == Self.yearlyID } }
    var stickerPack: Product? { products.first { $0.id == Self.stickerPackID } }

    var hasStickers: Bool { isPro || hasStickerPack }

    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.yearlyID, Self.stickerPackID])
        } catch {
            print("Pinscape: products unavailable: \(error)")
        }
        hasLoadedProducts = true
    }

    func refreshEntitlements() async {
        var pro = false
        var stickers = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if Self.subscriptionIDs.contains(transaction.productID) {
                if let expiry = transaction.expirationDate, expiry < Date() { continue }
                pro = true
            } else if transaction.productID == Self.stickerPackID {
                stickers = true
            }
        }
        isPro = pro || PinStore.isDemoPro
        hasStickerPack = stickers
        AppGroup.defaults.set(pro, forKey: SharedKeys.isPro)
        AppGroup.defaults.set(stickers, forKey: SharedKeys.hasStickerPack)
    }

    /// Handles the result of SwiftUI's `purchase` action. Returns true when something was bought.
    @discardableResult
    func handle(_ result: Product.PurchaseResult) async -> Bool {
        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return false }
            await transaction.finish()
            await refreshEntitlements()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    func restore() async {
        try? await AppStore.sync()
        await refreshEntitlements()
    }
}
