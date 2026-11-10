import SwiftUI
import FirebaseCore
import GoogleSignIn
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        return true
    }
}

@main
struct GituarApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var viewModel = ChordViewModel()
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appTheme") private var appTheme = "system"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(authViewModel)
                // Ayarlar › Tema
                .preferredColorScheme(appTheme == "light" ? .light : appTheme == "dark" ? .dark : nil)
                .onAppear {
                    AdMobManager.shared.updateConsent()
                    // Gituar Pro (StoreKit 2 + hediye Pro) — durum AdMobManager.isAdFree'yi besler
                    ProManager.shared.start()
                    InterstitialAdManager.shared.preload()
                    // İndirilmiş şarkı kopyası (varsa) belleğe alınır
                    OfflineStore.shared.start()
                    AppOpenAdManager.shared.preload()
                }
                .onOpenURL { url in
                    if url.scheme == "gituar" {
                        viewModel.handleDeepLink(url)
                    } else {
                        GIDSignIn.sharedInstance.handle(url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }
                    // Ön plana dönüşte: profil kontrolü, açılış reklamı (günde en fazla 3).
                    // Şarkılar ekran açıldıkça API'den istenir; arka planda katalog senkronu yok.
                    authViewModel.refreshProfileIfNeeded()
                    AppOpenAdManager.shared.showIfEligible()
                }
        }
    }
}
