import Foundation
import StoreKit
import Combine
import FirebaseAuth
import FirebaseFirestore

// MARK: - ProManager
//
// "Gituar Pro" iki yoldan gelir:
// 1. App Store aboneliği — aylık 99 TL, otomatik yenilenir (StoreKit 2). Sonuç `users/{uid}.pro` alanına yazılır (web okur).
// 2. Hediye Pro — yöneticinin verdiği `users/{uid}.proGrant = { active, until?, note, by, at }`. Yalnızca yönetici yazabilir
//    (Firestore kuralları); uygulama yalnızca okur.
// İkisinden biri geçerliyse kullanıcı Pro sayılır ve uygulamada hiçbir reklam yüklenmez (AdMobManager.isAdFree).
// Ürün App Store Connect'te `com.gituar.pro.monthly` kimliğiyle tanımlanmalıdır.

@MainActor
final class ProManager: ObservableObject {

    static let shared = ProManager()
    static let productID = "com.gituar.pro.monthly"

    /// App Store aboneliği ya da geçerli hediye Pro
    @Published private(set) var isPro = false
    /// App Store aboneliğinin yenilenme tarihi
    @Published private(set) var expirationDate: Date?
    /// Hediye Pro aktif mi ve ne zamana kadar (nil = süresiz)
    @Published private(set) var isGifted = false
    @Published private(set) var giftUntil: Date?
    /// Yalnızca App Store aboneliği (Firestore'a yalnızca bu yazılır; hediye ile karışmaz)
    private var isSubscribed = false
    @Published private(set) var products: [Product] = []
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?

    var monthlyProduct: Product? { products.first { $0.id == Self.productID } }

    private var updatesTask: Task<Void, Never>?
    private var authHandle: AuthStateDidChangeListenerHandle?
    private var grantListener: ListenerRegistration?
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

        // Giriş yapıldığında: abonelik durumunu kullanıcının dokümanına yaz (web için) ve hediye Pro'yu dinle.
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.writeSubscriptionToFirestore()
                self?.listenForGrant(uid: user.flatMap { $0.isAnonymous ? nil : $0.uid })
            }
        }

        Task {
            await loadProducts()
            await refreshEntitlements()
        }
    }

    func loadProducts() async {
        do {
            products = try await Product.products(for: [Self.productID])
            if products.isEmpty { print("⚠️ ProManager: \(Self.productID) App Store Connect'te bulunamadı.") }
        } catch {
            print("⚠️ ProManager: ürünler yüklenemedi: \(error.localizedDescription)")
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
                return isPro
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
        let changed = active != isSubscribed || until != expirationDate
        isSubscribed = active
        expirationDate = until
        if changed { print("ℹ️ ProManager: abonelik=\(active) until=\(until.map { "\($0)" } ?? "-")") }
        updatePro()
        writeSubscriptionToFirestore()
    }

    /// Abonelik ya da hediye: biri geçerliyse Pro; reklamlar buna göre açılır/kapanır.
    private func updatePro() {
        let giftValid = isGifted && (giftUntil.map { $0 > Date() } ?? true)
        isPro = isSubscribed || giftValid
        AdMobManager.shared.isAdFree = isPro
    }

    // MARK: - Hediye Pro

    /// `users/{uid}.proGrant` alanını canlı dinler (yönetici verdiğinde ya da geri aldığında hemen yansır).
    private func listenForGrant(uid: String?) {
        grantListener?.remove()
        grantListener = nil
        guard let uid else { isGifted = false; giftUntil = nil; updatePro(); return }
        grantListener = Firestore.firestore().collection("users").document(uid).addSnapshotListener { [weak self] snap, _ in
            let grant = snap?.data()?["proGrant"] as? [String: Any]
            let active = grant?["active"] as? Bool ?? false
            let until = (grant?["until"] as? Timestamp)?.dateValue()
            Task { @MainActor in
                guard let self else { return }
                self.isGifted = active
                self.giftUntil = until
                self.updatePro()
            }
        }
    }

    /// `users/{uid}.pro = { active, until, source, productId }` — yalnızca App Store aboneliği (web bu alandan okur).
    private func writeSubscriptionToFirestore() {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else { return }
        var pro: [String: Any] = [
            "active": isSubscribed,
            "source": "ios",
            "productId": Self.productID,
            "updatedAt": FieldValue.serverTimestamp(),
        ]
        pro["until"] = expirationDate.map { Timestamp(date: $0) } ?? NSNull()
        Firestore.firestore().collection("users").document(user.uid).setData(["pro": pro], merge: true) { error in
            if let error { print("⚠️ ProManager: pro alanı yazılamadı: \(error.localizedDescription)") }
        }
    }
}
