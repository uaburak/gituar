import Foundation
import UserMessagingPlatform
import GoogleMobileAds
import AppTrackingTransparency
import Combine

class AdMobManager: NSObject, ObservableObject {
    static let shared = AdMobManager()
    
    /// Pro kullanıcıda hiçbir reklam yüklenmez/gösterilmez. Açılışta son bilinen Pro durumuyla başlar
    /// (ProManager doğrulayana kadar Pro kullanıcıya reklam bir an bile görünmesin).
    @Published var isAdFree = UserDefaults.standard.bool(forKey: "lastKnownPro") {
        didSet { UserDefaults.standard.set(isAdFree, forKey: "lastKnownPro") }
    }
    @Published var isSdkInitialized = false
    private var isMobileAdsStartCalled = false
    
    func updateConsent() {
        let parameters = RequestParameters()
        
        ConsentInformation.shared.requestConsentInfoUpdate(with: parameters) { [weak self] error in
            if let error = error {
                print("Consent info update error: \(error.localizedDescription)")
                self?.initializeMobileAds()
                return
            }
            
            ConsentForm.loadAndPresentIfRequired(from: nil) { [weak self] loadAndPresentError in
                if let loadAndPresentError = loadAndPresentError {
                    print("Consent form error: \(loadAndPresentError.localizedDescription)")
                }
                
                if ConsentInformation.shared.canRequestAds {
                    self?.initializeMobileAds()
                }
            }
        }
        
        if ConsentInformation.shared.canRequestAds {
            initializeMobileAds()
        }
    }
    
    private func initializeMobileAds() {
        guard !isMobileAdsStartCalled else { return }
        isMobileAdsStartCalled = true
        
        DispatchQueue.main.async { [weak self] in
            MobileAds.shared.start { _ in
                DispatchQueue.main.async {
                    self?.isSdkInitialized = true
                }
            }
        }
    }
    
    func requestATT() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            ATTrackingManager.requestTrackingAuthorization { _ in
                self.initializeMobileAds()
            }
        }
    }
}
