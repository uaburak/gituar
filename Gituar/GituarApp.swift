import SwiftUI
import FirebaseCore
import GoogleSignIn
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        // NOT: ChordsStorageManager.startIfNeeded() GituarApp içinden @MainActor context'te çağrılıyor.
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
                .environmentObject(ChordsStorageManager.shared)
                .onAppear {
                    AdMobManager.shared.updateConsent()
                    // Gituar Plus (StoreKit 2) — hak durumu AdMobManager.isAdFree'yi besler
                    PlusManager.shared.start()
                    // Paketteki seed'i aç, ardından Firestore'dan farkları çek
                    ChordsStorageManager.shared.startIfNeeded()
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
                    // Ön plana dönüşte: seed yüklenemediyse yeniden dene, profil kontrolü,
                    // Firestore'dan katalog farklarını çek (en fazla 6 saatte bir), açılış reklamı (günde en fazla 3).
                    ChordsStorageManager.shared.retryIfFailed()
                    authViewModel.refreshProfileIfNeeded()
                    Task { await ChordsStorageManager.shared.checkForUpdates() }
                    AppOpenAdManager.shared.showIfEligible()
                }
        }
    }
}
