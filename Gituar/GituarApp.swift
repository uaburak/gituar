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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(authViewModel)
                .onAppear {
                    AdMobManager.shared.updateConsent()
                    // Gituar Plus (StoreKit 2) — hak durumu AdMobManager.isAdFree'yi besler
                    PlusManager.shared.start()
                    InterstitialAdManager.shared.preload()
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
