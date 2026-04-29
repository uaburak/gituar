import SwiftUI
#if canImport(GoogleMobileAds)
import GoogleMobileAds

struct AdBannerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let view = GADBannerView(adSize: GADAdSizeBanner)
        let viewController = UIViewController()
        view.adUnitID = "AD_UNIT_ID_BURAYA_GELECEK" // AdMob'dan aldığın ID
        view.rootViewController = viewController
        
        // Auto Layout for the banner
        view.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: viewController.view.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: viewController.view.centerYAnchor)
        ])
        
        view.load(GADRequest())
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#else
struct AdBannerView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 24))
                Text("GoogleMobileAds SDK Eksik")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                Text("Lütfen SPM üzerinden yükleyin.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
    }
}
#endif
