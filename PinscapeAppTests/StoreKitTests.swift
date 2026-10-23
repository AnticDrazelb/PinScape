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
        await ProStore.shared.refreshEntitlements()
    }

    override func tearDown() async throws {
        session.clearTransactions()
        await ProStore.shared.refreshEntitlements()
    }

    private func buy(_ id: String) async throws -> Transaction {
        let products = try await Product.products(for: [id])
        let product = try XCTUnwrap(products.first)
        let result = try await product.purchase()
        guard case .success(.verified(let transaction)) = result else {
            XCTFail("Purchase of \(id) didn't succeed: \(result)")
            throw CancellationError()
        }
        await transaction.finish()
        await ProStore.shared.refreshEntitlements()
        return transaction
    }

    func testStartsFree() {
        XCTAssertFalse(ProStore.shared.isPro)
        XCTAssertFalse(PinscapePlan.isPro)
    }

    func testMonthlyUnlocksPro() async throws {
        _ = try await buy(Entitlements.monthlyID)
        XCTAssertTrue(ProStore.shared.isPro)
        XCTAssertTrue(PinscapePlan.isPro, "extensions read the shared cache")
        XCTAssertNotNil(AppGroup.defaults.object(forKey: SharedKeys.proExpiresAt), "the cache records when Pro lapses")
    }

    func testExpiredSubscriptionLosesPro() async throws {
        _ = try await buy(Entitlements.yearlyID)
        XCTAssertTrue(ProStore.shared.isPro)
        try session.expireSubscription(productIdentifier: Entitlements.yearlyID)
        await ProStore.shared.refreshEntitlements()
        XCTAssertFalse(ProStore.shared.isPro)
        XCTAssertFalse(PinscapePlan.isPro)
    }

    func testRefundRevokesPro() async throws {
        let transaction = try await buy(Entitlements.monthlyID)
        try session.refundTransaction(identifier: UInt(transaction.id))
        await ProStore.shared.refreshEntitlements()
        XCTAssertFalse(ProStore.shared.isPro)
    }

    func testCachedProDoesNotOutliveItsExpiry() {
        AppGroup.defaults.set(true, forKey: SharedKeys.isPro)
        AppGroup.defaults.set(Date().addingTimeInterval(-60), forKey: SharedKeys.proExpiresAt)
        XCTAssertFalse(PinscapePlan.isPro, "a lapsed subscription mustn't unlock Pro in an extension")
        AppGroup.defaults.set(Date().addingTimeInterval(3600), forKey: SharedKeys.proExpiresAt)
        XCTAssertTrue(PinscapePlan.isPro)
    }

    func testAskToBuyStaysFreeUntilApproved() async throws {
        session.askToBuyEnabled = true
        let products = try await Product.products(for: [Entitlements.monthlyID])
        let product = try XCTUnwrap(products.first)
        let result = try await product.purchase()
        let bought = await ProStore.shared.handle(result)
        XCTAssertFalse(bought)
        XCTAssertFalse(ProStore.shared.isPro)
    }

    func testStickerPackIsSeparateFromPro() async throws {
        _ = try await buy(Entitlements.stickerPackID)
        XCTAssertTrue(ProStore.shared.hasStickerPack)
        XCTAssertTrue(ProStore.shared.hasStickers)
        XCTAssertFalse(ProStore.shared.isPro)
    }
}
