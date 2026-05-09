import SwiftUI
import Combine
#if canImport(GoogleMobileAds)
import GoogleMobileAds

class NativeAdViewModel: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    private var adLoader: AdLoader!
    
    // Debug modunda ve TestFlight ortamında test reklamları gösterilir.
    // Yalnızca App Store'dan indirildiğinde gerçek reklamlar (Release) kullanılır.
    var adUnitID: String {
        #if DEBUG
        return "ca-app-pub-3940256099942544/3986624511" // Test Native Ad ID
        #else
        // TestFlight kontrolü
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "ca-app-pub-3940256099942544/3986624511" // TestFlight için Test Native Ad ID
        }
        return "ca-app-pub-9748717269838207/3275621944" // Gerçek Ad Unit ID
        #endif
    }
    
    override init() {
        super.init()
        // SDK başlatılmamışsa çalışmayabilir diye garantiye alıyoruz
        MobileAds.shared.start(completionHandler: nil)
        loadAd()
    }
    
    func loadAd() {
        let options = NativeAdImageAdLoaderOptions()
        options.shouldRequestMultipleImages = false
        
        adLoader = AdLoader(
            adUnitID: adUnitID,
            rootViewController: nil,
            adTypes: [.native],
            options: [options]
        )
        adLoader.delegate = self
        adLoader.load(Request())
    }
    
    func adLoader(_ adLoader: AdLoader, didReceive nativeAd: NativeAd) {
        print("Native reklam başarıyla yüklendi!")
        self.nativeAd = nativeAd
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("Native Ad yüklenemedi: \(error.localizedDescription)")
    }
}

struct GituarNativeAdViewRepresentable: UIViewRepresentable {
    var nativeAd: NativeAd

    func makeUIView(context: Context) -> GoogleMobileAds.NativeAdView {
        let nativeAdView = GoogleMobileAds.NativeAdView()
        
        // Native UI Bileşenlerini Programatik Olarak Oluşturma
        nativeAdView.backgroundColor = UIColor.systemBackground
        nativeAdView.layer.cornerRadius = 20
        nativeAdView.clipsToBounds = true
        nativeAdView.layer.borderWidth = 1
        nativeAdView.layer.borderColor = UIColor.systemGray5.cgColor
        
        // Icon View
        let iconView = UIImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.layer.cornerRadius = 12
        iconView.clipsToBounds = true
        iconView.contentMode = .scaleAspectFill
        nativeAdView.addSubview(iconView)
        nativeAdView.iconView = iconView
        
        // Headline View
        let headlineView = UILabel()
        headlineView.translatesAutoresizingMaskIntoConstraints = false
        headlineView.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        headlineView.textColor = UIColor.label
        headlineView.numberOfLines = 1
        nativeAdView.addSubview(headlineView)
        nativeAdView.headlineView = headlineView
        
        // Body View
        let bodyView = UILabel()
        bodyView.translatesAutoresizingMaskIntoConstraints = false
        bodyView.font = UIFont.systemFont(ofSize: 13, weight: .regular)
        bodyView.textColor = UIColor.secondaryLabel
        bodyView.numberOfLines = 2
        nativeAdView.addSubview(bodyView)
        nativeAdView.bodyView = bodyView
        
        // Call To Action Button
        let ctaButton = UIButton(type: .system)
        ctaButton.translatesAutoresizingMaskIntoConstraints = false
        ctaButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        ctaButton.backgroundColor = UIColor.systemBlue
        ctaButton.setTitleColor(.white, for: .normal)
        ctaButton.layer.cornerRadius = 16
        ctaButton.clipsToBounds = true
        nativeAdView.addSubview(ctaButton)
        nativeAdView.callToActionView = ctaButton
        
        // Ad Badge
        let adBadge = UILabel()
        adBadge.translatesAutoresizingMaskIntoConstraints = false
        adBadge.text = "Reklam"
        adBadge.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        adBadge.textColor = .white
        adBadge.backgroundColor = UIColor.systemOrange
        adBadge.layer.cornerRadius = 4
        adBadge.clipsToBounds = true
        adBadge.textAlignment = .center
        nativeAdView.addSubview(adBadge)
        
        // Layout Constraints
        NSLayoutConstraint.activate([
            // Icon Constraints
            iconView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 16),
            iconView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 16),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            
            // Ad Badge Constraints
            adBadge.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            adBadge.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 16),
            adBadge.widthAnchor.constraint(equalToConstant: 44),
            adBadge.heightAnchor.constraint(equalToConstant: 16),
            
            // Headline Constraints
            headlineView.leadingAnchor.constraint(equalTo: adBadge.trailingAnchor, constant: 8),
            headlineView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
            headlineView.centerYAnchor.constraint(equalTo: adBadge.centerYAnchor),
            
            // Body Constraints
            bodyView.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            bodyView.topAnchor.constraint(equalTo: headlineView.bottomAnchor, constant: 4),
            bodyView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
            
            // Call To Action Constraints
            ctaButton.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 16),
            ctaButton.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -16),
            ctaButton.topAnchor.constraint(equalTo: bodyView.bottomAnchor, constant: 12),
            ctaButton.heightAnchor.constraint(equalToConstant: 40),
            ctaButton.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -16)
        ])
        
        return nativeAdView
    }

    func updateUIView(_ nativeAdView: GoogleMobileAds.NativeAdView, context: Context) {
        // Populate the native ad view with the native ad assets.
        (nativeAdView.headlineView as? UILabel)?.text = nativeAd.headline
        (nativeAdView.bodyView as? UILabel)?.text = nativeAd.body
        (nativeAdView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        (nativeAdView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        
        // Hide elements if they don't have content
        nativeAdView.iconView?.isHidden = nativeAd.icon == nil
        nativeAdView.bodyView?.isHidden = nativeAd.body == nil
        
        // Associate the native ad view with the native ad object
        nativeAdView.nativeAd = nativeAd
    }
}

struct GituarNativeAdContainer: View {
    @StateObject private var viewModel = NativeAdViewModel()
    
    var body: some View {
        Group {
            if let nativeAd = viewModel.nativeAd {
                GituarNativeAdViewRepresentable(nativeAd: nativeAd)
                    .frame(height: 140)
                    .glassEffect(in: .rect(cornerRadius: 20.0))
            } else {
                // Şık Yükleniyor Veya Fallback Görünümü
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray5))
                        .frame(width: 48, height: 48)
                        .shimmering()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 16)
                            .shimmering()
                        
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                            .frame(height: 12)
                            .padding(.trailing, 40)
                            .shimmering()
                    }
                }
                .padding(16)
                .frame(height: 140, alignment: .top)
                .background(Color(.systemBackground).opacity(0.5))
                .glassEffect(in: .rect(cornerRadius: 20.0))
            }
        }
    }
}

// Basit Shimmer Effect eklentisi
extension View {
    func shimmering() -> some View {
        self.opacity(0.6)
    }
}
#else
struct GituarNativeAdContainer: View {
    var body: some View {
        EmptyView()
    }
}
#endif
