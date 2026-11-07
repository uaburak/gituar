import SwiftUI
import UIKit
#if canImport(GoogleMobileAds)
import GoogleMobileAds
#endif

// MARK: - AdConfig
//
// Tüm reklam birimleri ve frekans kuralları tek yerde (docs/PLATFORM-PLAN.md §6).
// Pro kullanıcısı (AdMobManager.isAdFree) için hiçbir yerleşim reklam yüklemez.

nonisolated enum AdConfig {
    static let banner = "ca-app-pub-9748717269838207/3275621944"
    static let native = "ca-app-pub-9748717269838207/4478703611"

    // AdMob birimleri (2026-11-05'te oluşturuldu): "Geçiş - Şarkı" ve "Açılış". DEBUG'da Google test birimleri kullanılır.
    private static let interstitialProduction = "ca-app-pub-9748717269838207/7548725985"
    private static let appOpenProduction = "ca-app-pub-9748717269838207/7980357868"

    static var interstitial: String? { resolve(interstitialProduction, test: "ca-app-pub-3940256099942544/4411468910") }
    static var appOpen: String? { resolve(appOpenProduction, test: "ca-app-pub-3940256099942544/5575463023") }

    private static func resolve(_ production: String, test: String) -> String? {
        #if DEBUG
        return test
        #else
        return production.contains("REPLACE") ? nil : production
        #endif
    }

    /// Her kaçıncı şarkı açılışında geçiş reklamı gösterilir.
    static let interstitialEveryNthSong = 4
    /// İki geçiş reklamı arasındaki en kısa süre.
    static let interstitialMinInterval: TimeInterval = 90
    /// Günde en fazla kaç açılış reklamı.
    static let appOpenMaxPerDay = 3
    /// Yüklenen açılış reklamı bu süreden eskiyse gösterilmez (Google önerisi 4 saat).
    static let appOpenMaxAge: TimeInterval = 4 * 60 * 60
    /// Listelerde kaç satırda bir yerel reklam.
    static let nativeAdEveryNRows = 10
}

nonisolated enum AdPlacements {
    /// Listelerde `index` satırından sonra yerel reklam gösterilsin mi?
    static func shouldShowNativeAd(afterRow index: Int, isAdFree: Bool) -> Bool {
        !isAdFree && (index + 1) % AdConfig.nativeAdEveryNRows == 0
    }
}

// MARK: - List & sticky placements

/// Liste satırları arasına giren yerel reklam satırı.
struct NativeAdRow: View {
    var body: some View {
        AdNativeView()
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// Şarkı sayfasında satır içi reklam: şarkının başında ve şarkı biter bitmez birer tane.
/// Pro'da hiç görünmez; yüklenene kadar yer kaplamaz.
struct SongAdSlot: View {
    @ObservedObject private var adMobManager = AdMobManager.shared

    var body: some View {
        if !adMobManager.isAdFree {
            AdNativeView()
                .frame(maxWidth: .infinity)
        }
    }
}

#if canImport(GoogleMobileAds)

// MARK: - Helpers

extension UIApplication {
    /// Tam ekran reklamın sunulacağı en üstteki view controller.
    static func topViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        var top = keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Aynı anda iki tam ekran reklam sunulmasın diye ortak durum.
/// Sunum geri çağrısı hiç gelmezse bayrak 5 dk sonra kendiliğinden düşer (reklamlar sonsuza dek kilitlenmesin).
@MainActor
enum FullScreenAdState {
    private static var presentingSince: Date?
    /// Son tam ekran reklamın kapandığı an (açılış reklamı, geçiş reklamının hemen ardından gelmesin).
    static var lastDismissedAt: Date?

    static var isPresenting: Bool {
        get {
            guard let since = presentingSince else { return false }
            if Date().timeIntervalSince(since) > 5 * 60 { presentingSince = nil; return false }
            return true
        }
        set { presentingSince = newValue ? Date() : nil }
    }

    /// Reklamın sunulabileceği, geçiş animasyonu olmayan ve üstünde modal bulunmayan en üst view controller.
    /// Navigation push sürerken sunulan tam ekran reklamlar kapanmayabiliyor; o an uygun değilse nil döner.
    static func readyPresenter() -> UIViewController? {
        guard let top = UIApplication.topViewController() else { return nil }
        guard top.view.window != nil, !top.isBeingDismissed, !top.isBeingPresented, top.presentedViewController == nil else { return nil }
        guard top.transitionCoordinator == nil else { return nil }
        if let nav = findNavigationController(in: top), nav.transitionCoordinator != nil { return nil }
        return top
    }

    private static func findNavigationController(in vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController { return nav }
        for child in vc.children {
            if let nav = findNavigationController(in: child) { return nav }
        }
        return nil
    }

    /// `attempts` kez, yarım saniye arayla uygun bir sunucu bekler; bulunca `present` çağrılır.
    static func whenReady(attempts: Int = 6, _ present: @escaping @MainActor (UIViewController) -> Void) {
        if let presenter = readyPresenter() { present(presenter); return }
        guard attempts > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            whenReady(attempts: attempts - 1, present)
        }
    }
}

// MARK: - InterstitialAdManager

/// Her 4. şarkı açılışında, en az 90 sn arayla geçiş reklamı. Pro'da hiç.
@MainActor
final class InterstitialAdManager: NSObject, FullScreenContentDelegate {

    static let shared = InterstitialAdManager()

    private var ad: InterstitialAd?
    private var isLoading = false
    private var songOpenCount = 0
    private var lastShownAt: Date?

    private override init() { super.init() }

    func preload() {
        guard let unitID = AdConfig.interstitial, ad == nil, !isLoading else { return }
        guard AdMobManager.shared.isSdkInitialized, !AdMobManager.shared.isAdFree else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let loaded = try await InterstitialAd.load(with: unitID, request: Request())
                loaded.fullScreenContentDelegate = self
                ad = loaded
            } catch {
                print("⚠️ Interstitial yüklenemedi: \(error.localizedDescription)")
            }
        }
    }

    /// Şarkı detayı her açıldığında (ve listede ileri/geri geçişte) çağrılır.
    func registerSongOpen() {
        guard !AdMobManager.shared.isAdFree else { return }
        songOpenCount += 1
        print("📣 Şarkı açılışı #\(songOpenCount) (geçiş reklamı yüklü: \(ad != nil))")
        guard songOpenCount % AdConfig.interstitialEveryNthSong == 0 else {
            preload()
            return
        }
        if let lastShownAt, Date().timeIntervalSince(lastShownAt) < AdConfig.interstitialMinInterval { return }
        guard ad != nil, !FullScreenAdState.isPresenting else {
            preload()
            return
        }
        // Sayfa geçişi bitmeden sunma: animasyon sürerken sunulan reklamın kapatma düğmesi çalışmıyordu.
        FullScreenAdState.whenReady { [weak self] presenter in
            guard let self, let ad = self.ad, !FullScreenAdState.isPresenting else { return }
            FullScreenAdState.isPresenting = true
            self.lastShownAt = Date()
            self.ad = nil
            print("📣 Interstitial sunuluyor")
            ad.present(from: presenter)
        }
    }

    // MARK: FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📣 Interstitial kapandı")
        FullScreenAdState.isPresenting = false
        FullScreenAdState.lastDismissedAt = Date()
        preload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("⚠️ Interstitial gösterilemedi: \(error.localizedDescription)")
        FullScreenAdState.isPresenting = false
        self.ad = nil
        preload()
    }
}

// MARK: - AppOpenAdManager

/// Uygulama ön plana gelince açılış reklamı; günde en fazla 3, Pro'da hiç.
@MainActor
final class AppOpenAdManager: NSObject, FullScreenContentDelegate {

    static let shared = AppOpenAdManager()

    private var ad: AppOpenAd?
    private var loadedAt: Date?
    private var isLoading = false
    private let countKey = "appOpenAd.count"
    private let dayKey = "appOpenAd.day"

    private override init() { super.init() }

    private var todayKey: String {
        let day = Calendar.current.startOfDay(for: Date())
        return ISO8601DateFormatter().string(from: day)
    }

    private var shownToday: Int {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: dayKey) == todayKey else { return 0 }
        return defaults.integer(forKey: countKey)
    }

    private func incrementShownToday() {
        let defaults = UserDefaults.standard
        let count = shownToday + 1
        defaults.set(todayKey, forKey: dayKey)
        defaults.set(count, forKey: countKey)
    }

    func preload() {
        guard let unitID = AdConfig.appOpen, ad == nil, !isLoading else { return }
        guard AdMobManager.shared.isSdkInitialized, !AdMobManager.shared.isAdFree else { return }
        guard shownToday < AdConfig.appOpenMaxPerDay else { return }
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                let loaded = try await AppOpenAd.load(with: unitID, request: Request())
                loaded.fullScreenContentDelegate = self
                ad = loaded
                loadedAt = Date()
            } catch {
                print("⚠️ App open reklamı yüklenemedi: \(error.localizedDescription)")
            }
        }
    }

    /// scenePhase == .active olduğunda çağrılır.
    func showIfEligible() {
        guard !AdMobManager.shared.isAdFree, !FullScreenAdState.isPresenting else { return }
        guard shownToday < AdConfig.appOpenMaxPerDay else { return }
        // Başka bir tam ekran reklam az önce kapandıysa (ör. reklamdan App Store'a gidip dönüldü) üstüne açılış reklamı bindirme
        if let last = FullScreenAdState.lastDismissedAt, Date().timeIntervalSince(last) < 60 { return }
        guard ad != nil, let loadedAt, Date().timeIntervalSince(loadedAt) < AdConfig.appOpenMaxAge else {
            self.ad = nil
            preload()
            return
        }
        FullScreenAdState.whenReady(attempts: 2) { [weak self] presenter in
            guard let self, let ad = self.ad, !FullScreenAdState.isPresenting else { return }
            FullScreenAdState.isPresenting = true
            self.ad = nil
            self.incrementShownToday()
            print("📣 Açılış reklamı sunuluyor")
            ad.present(from: presenter)
        }
    }

    // MARK: FullScreenContentDelegate

    func adDidDismissFullScreenContent(_ ad: FullScreenPresentingAd) {
        print("📣 Açılış reklamı kapandı")
        FullScreenAdState.isPresenting = false
        FullScreenAdState.lastDismissedAt = Date()
        preload()
    }

    func ad(_ ad: FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        print("⚠️ App open reklamı gösterilemedi: \(error.localizedDescription)")
        FullScreenAdState.isPresenting = false
        self.ad = nil
        preload()
    }
}

#else

/// SDK yokken derlensin diye boş yerleşimler.
@MainActor final class InterstitialAdManager {
    static let shared = InterstitialAdManager()
    func preload() {}
    func registerSongOpen() {}
}
@MainActor final class AppOpenAdManager {
    static let shared = AppOpenAdManager()
    func preload() {}
    func showIfEligible() {}
}

#endif
