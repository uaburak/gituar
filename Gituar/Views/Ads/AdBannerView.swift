import SwiftUI
import Combine
#if canImport(GoogleMobileAds)
import GoogleMobileAds

// MARK: - Banner Ad View
struct AdBannerView: UIViewControllerRepresentable {
    let viewWidth: CGFloat
    
    var adUnitID: String {
        return "ca-app-pub-9748717269838207/3275621944"
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        
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
        
        MobileAds.shared.start(completionHandler: nil)
        context.coordinator.errorLabel = errorLabel
        bannerView.load(Request())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, BannerViewDelegate {
        weak var errorLabel: UILabel?
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { errorLabel?.isHidden = true }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            errorLabel?.text = "Reklam yüklenemedi"
        }
    }
}

// MARK: - Native Ad View (Yerel Gelişmiş)
class NativeAdViewModel: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    private var adLoader: AdLoader!
    
    func loadAd(adUnitID: String) {
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
        self.nativeAd = nativeAd
    }
    
    func adLoader(_ adLoader: AdLoader, didFailToReceiveAdWithError error: Error) {
        print("Native Ad Error: \(error.localizedDescription)")
    }
}

struct NativeAdViewWrapper: UIViewRepresentable {
    var nativeAd: NativeAd
    
    func makeUIView(context: Context) -> NativeAdView {
        let nativeAdView = NativeAdView()
        
        let headlineLabel = UILabel()
        headlineLabel.font = .systemFont(ofSize: 16, weight: .bold)
        headlineLabel.numberOfLines = 1
        
        let bodyLabel = UILabel()
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabel
        bodyLabel.numberOfLines = 2
        
        let iconView = UIImageView()
        iconView.layer.cornerRadius = 8
        iconView.clipsToBounds = true
        iconView.contentMode = .scaleAspectFill
        
        let callToActionButton = UIButton(type: .system)
        callToActionButton.backgroundColor = .systemBlue
        callToActionButton.setTitleColor(.white, for: .normal)
        callToActionButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
        callToActionButton.layer.cornerRadius = 10
        callToActionButton.isUserInteractionEnabled = false 
        
        let adBadge = UILabel()
        adBadge.text = "Reklam"
        adBadge.font = .systemFont(ofSize: 10, weight: .bold)
        adBadge.textColor = .systemBackground
        adBadge.backgroundColor = .systemOrange
        adBadge.layer.cornerRadius = 4
        adBadge.clipsToBounds = true
        adBadge.textAlignment = .center
        
        nativeAdView.addSubview(iconView)
        nativeAdView.addSubview(headlineLabel)
        nativeAdView.addSubview(bodyLabel)
        nativeAdView.addSubview(callToActionButton)
        nativeAdView.addSubview(adBadge)
        
        nativeAdView.headlineView = headlineLabel
        nativeAdView.bodyView = bodyLabel
        nativeAdView.iconView = iconView
        nativeAdView.callToActionView = callToActionButton
        
        [iconView, headlineLabel, bodyLabel, callToActionButton, adBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            iconView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 45),
            iconView.heightAnchor.constraint(equalToConstant: 45),
            
            headlineLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            headlineLabel.topAnchor.constraint(equalTo: iconView.topAnchor),
            headlineLabel.trailingAnchor.constraint(equalTo: adBadge.leadingAnchor, constant: -8),
            
            adBadge.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            adBadge.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 12),
            adBadge.widthAnchor.constraint(equalToConstant: 44),
            adBadge.heightAnchor.constraint(equalToConstant: 16),
            
            bodyLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            bodyLabel.topAnchor.constraint(equalTo: headlineLabel.bottomAnchor, constant: 4),
            bodyLabel.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            
            callToActionButton.leadingAnchor.constraint(equalTo: nativeAdView.leadingAnchor, constant: 12),
            callToActionButton.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -12),
            callToActionButton.bottomAnchor.constraint(equalTo: nativeAdView.bottomAnchor, constant: -12),
            callToActionButton.heightAnchor.constraint(equalToConstant: 40)
        ])
        
        return nativeAdView
    }
    
    func updateUIView(_ nativeAdView: NativeAdView, context: Context) {
        (nativeAdView.headlineView as? UILabel)?.text = nativeAd.headline
        (nativeAdView.bodyView as? UILabel)?.text = nativeAd.body
        (nativeAdView.iconView as? UIImageView)?.image = nativeAd.icon?.image
        (nativeAdView.callToActionView as? UIButton)?.setTitle(nativeAd.callToAction, for: .normal)
        nativeAdView.nativeAd = nativeAd
    }
}

struct AdNativeView: View {
    @StateObject private var viewModel = NativeAdViewModel()
    // Native Advanced ID: ca-app-pub-9748717269838207/4478703611
    let adUnitID: String = "ca-app-pub-9748717269838207/4478703611"
    
    var body: some View {
        ZStack {
            if let nativeAd = viewModel.nativeAd {
                NativeAdViewWrapper(nativeAd: nativeAd)
                    .frame(height: 140)
                    .glassEffect(in: .rect(cornerRadius: 20.0))
            } else {
                HStack {
                    ProgressView()
                        .padding(.trailing, 8)
                    Text("Reklam Yükleniyor...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .background(Color(.systemGray6))
                .cornerRadius(20)
            }
        }
        .onAppear {
            viewModel.loadAd(adUnitID: adUnitID)
        }
    }
}

#else
// SDK Olmadığında Çalışacak Placeholderlar
struct AdBannerView: View {
    var body: some View {
        Text("Banner (SDK Yok)")
            .frame(height: 50)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
    }
}

struct AdNativeView: View {
    var body: some View {
        Text("Native Ad (SDK Yok)")
            .frame(height: 140)
            .frame(maxWidth: .infinity)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
    }
}
#endif
