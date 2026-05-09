import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct AdBannerView: UIViewControllerRepresentable {
    let viewWidth: CGFloat
    
    // Sadece Banner reklam birimini kullanacağız. Test cihazları eklendiği için gerçek ID kullanılıyor.
    var adUnitID: String {
        return "ca-app-pub-9748717269838207/3275621944"
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear // Arkaplanı şeffaf yapıyoruz
        
        // Ekranda hatayı görebilmen için hata etiketi
        let errorLabel = UILabel()
        errorLabel.text = "Reklam yükleniyor..."
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: 12, weight: .medium)
        errorLabel.numberOfLines = 0
        errorLabel.textAlignment = .center
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(errorLabel)
        
        NSLayoutConstraint.activate([
            errorLabel.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor, constant: 16),
            errorLabel.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor, constant: -16)
        ])
        
        // Adaptive Banner kullanımı
        let adSize = largeAnchoredAdaptiveBanner(width: viewWidth)
        let bannerView = BannerView(adSize: adSize)
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            bannerView.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor)
        ])
        
        // Reklam başlatılmamış olma ihtimaline karşı zorunlu başlatma
        MobileAds.shared.start(completionHandler: nil)
        
        context.coordinator.errorLabel = errorLabel
        bannerView.load(Request())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        weak var errorLabel: UILabel?
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("🟢 REKLAM BAŞARIYLA YÜKLENDİ 🟢")
            errorLabel?.isHidden = true
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            let errorMsg = "🔴 REKLAM YÜKLENEMEDİ: \(error.localizedDescription)"
            print(errorMsg)
            errorLabel?.text = errorMsg
        }
    }
}
#else
struct AdBannerView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 100) // Yükseklik 100'e çıkarıldı
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                Text("Reklam Alanı (SDK Eksik)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal)
    }
}
#endif



