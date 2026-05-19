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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
                .environmentObject(authViewModel)
                .environmentObject(ChordsStorageManager.shared)
                .onAppear {
                    AdMobManager.shared.updateConsent()
                    // @MainActor context — Storage indirmesini güvenle başlat
                    ChordsStorageManager.shared.startIfNeeded()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
