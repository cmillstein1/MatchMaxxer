import Foundation
import StoreKit
import Observation

// StoreKit 2 wrapper for the single non-consumable Sound unlock.
//
// Design notes:
// - Holds an Observable view of `purchasedIDs` so any view can read
//   `Store.shared.isSoundUnlocked` and re-render reactively.
// - Refreshes entitlements on init, after a successful purchase, after a
//   `Restore`, and whenever Transaction.updates fires (e.g. an Ask-to-Buy
//   approval lands while the user is in the app).
// - We `await tx.finish()` for every verified transaction. Apple requires it
//   and forgetting it causes the same transaction to keep arriving in
//   Transaction.updates forever.
@MainActor
@Observable
final class Store {
    static let shared = Store()

    static let soundUnlockID = "com.millstein.MatchMaxxer.unlock.sound"
    static let hexUnlockID = "com.millstein.MatchMaxxer.unlock.hex"
    static let allProductIDs: [String] = [soundUnlockID, hexUnlockID]

    var products: [Product] = []
    var purchasedIDs: Set<String> = []
    var purchaseInProgress: Bool = false
    var lastError: String?

    var soundProduct: Product? {
        products.first { $0.id == Self.soundUnlockID }
    }
    var hexProduct: Product? {
        products.first { $0.id == Self.hexUnlockID }
    }
    var isSoundUnlocked: Bool {
        purchasedIDs.contains(Self.soundUnlockID)
    }
    var isHexUnlocked: Bool {
        purchasedIDs.contains(Self.hexUnlockID)
    }

    func productID(for category: GameCategory) -> String? {
        switch category {
        case .sound: return Self.soundUnlockID
        case .hex:   return Self.hexUnlockID
        case .color: return nil  // Free
        }
    }
    func product(for category: GameCategory) -> Product? {
        guard let id = productID(for: category) else { return nil }
        return products.first { $0.id == id }
    }
    func isUnlocked(_ category: GameCategory) -> Bool {
        switch category {
        case .color: return true
        case .sound: return isSoundUnlocked
        case .hex:   return isHexUnlocked
        }
    }

    private var updateListener: Task<Void, Never>?

    private init() {
        updateListener = listenForTransactions()
        Task { await refresh() }
    }
    // No deinit needed — singleton lives for the lifetime of the app.

    func refresh() async {
        await loadProducts()
        await updateEntitlements()
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.allProductIDs)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func updateEntitlements() async {
        var owned = Set<String>()
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result {
                owned.insert(tx.productID)
            }
        }
        purchasedIDs = owned
    }

    @discardableResult
    func purchase(_ product: Product) async -> PurchaseOutcome {
        guard !purchaseInProgress else { return .alreadyInProgress }
        purchaseInProgress = true
        defer { purchaseInProgress = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    await updateEntitlements()
                    return .success
                case .unverified(_, let error):
                    lastError = "Could not verify purchase: \(error.localizedDescription)"
                    return .unverified
                }
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .unknown
            }
        } catch {
            lastError = error.localizedDescription
            return .failed
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await updateEntitlements()
    }

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let tx) = result {
                    await tx.finish()
                    await self?.updateEntitlements()
                }
            }
        }
    }
}

enum PurchaseOutcome {
    case success
    case cancelled
    case pending
    case unverified
    case failed
    case alreadyInProgress
    case unknown
}
