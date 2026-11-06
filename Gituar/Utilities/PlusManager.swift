import Foundation
import StoreKit
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - PlusManager
//
// "Gituar Pro" — aylık 99 TL, otomatik yenilenen abonelik (StoreKit 2).
// Abonelik aktifken uygulamada hiçbir reklam yüklenmez (AdMobManager.isAdFree) ve durum
// `users/{uid}.plus` alanına yazılır; web sitesi aynı alandan okuyup reklamları kaldırır.
// Ürün App Store Connect'te `com.gituar.plus.monthly` kimliğiyle tanımlanmalıdır.

@MainActor
final class PlusManager: ObservableObject {

    static let shared = PlusManager()
    static let productID = "com.gituar.plus.monthly"

    @Published private(set) var isPlus = false
    @Published private(set) var expirationDate: Date?
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    var monthlyProduct: Product? { products.first { $0.id == Self.productID } }

    private var updatesTask: Task<Void, Never>?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var started = false

    private init() {}

    // MARK: - Lifecycle

    /// Uygulama açılışında bir kez çağrılır: ürünleri yükler, mevcut hakları okur, yeni işlemleri dinler.
    func start() {
        guard !started else { return }
        started = true

        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }

        // Giriş yapıldığında Plus durumunu kullanıcının dokümanına yaz (web için).
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor in self?.writePlusToFirestore() }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.productID])
            if products.isEmpty { print("⚠️ PlusManager: \(Self.productID) App Store Connect'te bulunamadı.") }
        } catch {
            print("⚠️ PlusManager: ürünler yüklenemedi: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase / Restore

    @discardableResult
    func purchase() async -> Bool {
        if monthlyProduct == nil { await loadProducts() }
        guard let product = monthlyProduct else {
            lastError = "Abonelik şu anda yüklenemedi. Lütfen daha sonra tekrar deneyin."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "Satın alma doğrulanamadı."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                return isPlus
            case .userCancelled:
                return false
            case .pending:
                lastError = "Satın alma onay bekliyor (Aile Paylaşımı / Satın Alma İzni)."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    // MARK: - Entitlements

    func refreshEntitlements() async {
        var active = false
        var until: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < Date() { continue }
            active = true
            until = transaction.expirationDate
        }
        apply(active: active, until: until)
    }

    private func apply(active: Bool, until: Date?) {
        let changed = active != isPlus || until != expirationDate
        isPlus = active
        expirationDate = until
        AdMobManager.shared.isAdFree = active
        if changed { print("ℹ️ PlusManager: isPlus=\(active) until=\(until.map { "\($0)" } ?? "-")") }
        writePlusToFirestore()
    }

    /// `users/{uid}.plus = { active, until, source, productId }` — web bu alandan okur.
    private func writePlusToFirestore() {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return }
        var plus: [String: Any] = [
            "active": isPlus,
            "source": "ios",
            "productId": Self.productID,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        plus["until"] = expirationDate.map { Timestamp(date: $0) } ?? NSNull()
        Firestore.firestore().collection("users").document(user.uid).setData(["plus": plus], merge: true) { error in
            if let error { print("⚠️ PlusManager: plus alanı yazılamadı: \(error.localizedDescription)") }
        }
    }
}
