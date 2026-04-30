import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct AdBannerView: UIViewControllerRepresentable {
    // Gerçek Ad Unit ID (ca-app-pub-9748717269838207/3275621944)
    let adUnitID: String = "ca-app-pub-9748717269838207/3275621944" 

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        // Daha yüksek bir alan için AdSizeLargeBanner (100pt) kullanıyoruz.
        let bannerView = BannerView(adSize: AdSizeLargeBanner)
        
        bannerView.adUnitID = adUnitID
        bannerView.rootViewController = viewController
        bannerView.delegate = context.coordinator
        
        bannerView.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(bannerView)
        
        NSLayoutConstraint.activate([
            bannerView.bottomAnchor.constraint(equalTo: viewController.view.safeAreaLayoutGuide.bottomAnchor),
            bannerView.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor)
        ])
        
        bannerView.load(Request())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, BannerViewDelegate {
        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            print("Reklam başarıyla yüklendi.")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            print("Reklam yükleme hatası: \(error.localizedDescription)")
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



