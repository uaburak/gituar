import UIKit

// MARK: - ScreenAwake
//
// Şarkı ekranı açıkken ekranın kararmasını/kilitlenmesini engeller — çalarken eller gitardadır.
// İç içe push edilen şarkı ekranları için referans sayar; sonuncusu kapanınca normale döner.

enum ScreenAwake {
    private static var holders = 0

    static func retain() {
        holders += 1
        // Ayarlar › Ekranı Açık Tut (varsayılan açık)
        let enabled = UserDefaults.standard.object(forKey: "keepScreenAwake") as? Bool ?? true
        UIApplication.shared.isIdleTimerDisabled = enabled
    }

    static func release() {
        holders = max(0, holders - 1)
        if holders == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
