import StoreKit
import StoreKitTest
import XCTest
@testable import Pinscape

/// The purchase lifecycle against the local StoreKit configuration: buying, lapsing, refunds,
/// Ask to Buy, and the Sticker Pack on its own.
@MainActor
final class StoreKitTests: XCTestCase {
    private var session: SKTestSession!

    override func setUp() async throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Pinscape", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.disableDialogs = true
        session.resetToDefaultState()
        session.clearTransactions()
        await settle { !$0.isPro && !$0.hasStickerPack }
    }

    override func tearDown() async throws {
        session.clearTransactions()
        await settle { !$0.isPro && !$0.hasStickerPack }
    }

    /// iOS 26.4 and 26.5 simulators serve nothing to `SKTestSession` (an Apple bug); there these
    /// tests skip. CI runs them on iOS 26.2 and fails if any skip.
    private func skipOnBrokenRuntime() throws {
        #if targetEnvironment(simulator)
        let os = ProcessInfo.processInfo.operatingSystemVersion
        if os.majorVersion == 26, (4...5).contains(os.minorVersion) {
            throw XCTSkip("StoreKit testing doesn't work on the iOS 26.\(os.minorVersion) simulator")
        }
        #endif
    }

    /// The test session applies purchases, expiries, refunds and resets asynchronously, so wait
    /// (briefly) for the entitlements to catch up before asserting on them.
    private func settle(within timeout: Duration = .seconds(10), until condition: (ProStore) -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        await ProStore.shared.refreshEntitlements()
        while !condition(ProStore.shared), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
            await ProStore.shared.refreshEntitlements()
        }
    }

    /// Buys through the test session. `Product.purchase()` waits for a confirmation sheet that a
    /// headless test can't show; the app's paywall uses SwiftUI's `purchase` action instead.
    private func buy(_ id: String) async throws -> Transaction {
        let transaction: Transaction
        do {
            transaction = try await session.buyProduct(identifier: id)
        } catch {
            try skipOnBrokenRuntime()
            throw error
        }
        await transaction.finish()
        return transaction
    }

    func testStartsFree() {
        XCTAssertFalse(ProStore.shared.isPro)
        XCTAssertFalse(PinscapePlan.isPro)
    }

    func testMonthlyUnlocksPro() async throws {
        _ = try await buy(Entitlements.monthlyID)
        await settle { $0.isPro }
        XCTAssertTrue(ProStore.shared.isPro)
        XCTAssertTrue(PinscapePlan.isPro, "extensions read the shared cache")
        XCTAssertNotNil(AppGroup.defaults.object(forKey: SharedKeys.proExpiresAt), "the cache records when Pro lapses")
    }

    func testExpiredSubscriptionLosesPro() async throws {
        _ = try await buy(Entitlements.yearlyID)
        await settle { $0.isPro }
        XCTAssertTrue(ProStore.shared.isPro)
        try session.expireSubscription(productIdentifier: Entitlements.yearlyID)
        await settle { !$0.isPro }
        XCTAssertFalse(ProStore.shared.isPro)
        XCTAssertFalse(PinscapePlan.isPro)
    }

    func testRefundRevokesPro() async throws {
        let transaction = try await buy(Entitlements.monthlyID)
        await settle { $0.isPro }
        XCTAssertTrue(ProStore.shared.isPro)
        try session.refundTransaction(identifier: UInt(transaction.id))
        await settle { !$0.isPro }
        XCTAssertFalse(ProStore.shared.isPro)
    }

    func testCachedProDoesNotOutliveItsExpiry() {
        AppGroup.defaults.set(true, forKey: SharedKeys.isPro)
        AppGroup.defaults.set(Date().addingTimeInterval(-60), forKey: SharedKeys.proExpiresAt)
        XCTAssertFalse(PinscapePlan.isPro, "a lapsed subscription mustn't unlock Pro in an extension")
        AppGroup.defaults.set(Date().addingTimeInterval(3600), forKey: SharedKeys.proExpiresAt)
        XCTAssertTrue(PinscapePlan.isPro)
    }

    func testPendingOrCancelledPurchasesStayFree() async {
        // Ask to Buy returns .pending until a parent approves; closing the sheet returns .userCancelled.
        let pending = await ProStore.shared.handle(.pending)
        let cancelled = await ProStore.shared.handle(.userCancelled)
        XCTAssertFalse(pending)
        XCTAssertFalse(cancelled)
        XCTAssertFalse(ProStore.shared.isPro)
    }

    func testCatalogMatchesThePaywall() async throws {
        let ids = [Entitlements.monthlyID, Entitlements.yearlyID, Entitlements.stickerPackID]
        let products = try await Product.products(for: ids)
        if products.isEmpty { try skipOnBrokenRuntime() }
        let prices = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0.displayPrice) })
        // The paywall shows these if the App Store can't be reached, so they must agree.
        XCTAssertEqual(prices[Entitlements.monthlyID], "£2.99")
        XCTAssertEqual(prices[Entitlements.yearlyID], "£24.99")
        XCTAssertEqual(prices[Entitlements.stickerPackID], "£9.99")
    }

    func testStickerPackIsSeparateFromPro() async throws {
        _ = try await buy(Entitlements.stickerPackID)
        await settle { $0.hasStickerPack }
        XCTAssertTrue(ProStore.shared.hasStickerPack)
        XCTAssertTrue(ProStore.shared.hasStickers)
        XCTAssertFalse(ProStore.shared.isPro)
    }
}
