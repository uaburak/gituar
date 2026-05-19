import SwiftUI
import Combine
#if canImport(GoogleMobileAds)
import GoogleMobileAds

// MARK: - Banner Ad View
struct AdBannerRepresentable: UIViewControllerRepresentable {
    let viewWidth: CGFloat
    @Binding var isFailed: Bool
    @Binding var isLoaded: Bool
    
    var adUnitID: String {
        return "ca-app-pub-9748717269838207/3275621944"
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        viewController.view.backgroundColor = .clear
        
        // Removed error label
        
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
        
        context.coordinator.parent = self
        bannerView.load(Request())

        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject, BannerViewDelegate {
        var parent: AdBannerRepresentable?
        
        func bannerViewDidReceiveAd(_ bannerView: BannerView) { 
            parent?.isLoaded = true 
            parent?.isFailed = false
        }
        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            parent?.isFailed = true
        }
    }
}

struct AdBannerView: View {
    let viewWidth: CGFloat
    @State private var isFailed = false
    @State private var isLoaded = false
    @ObservedObject private var adMobManager = AdMobManager.shared
    
    var body: some View {
        let adHeight = largeAnchoredAdaptiveBanner(width: viewWidth).size.height
        
        if isFailed {
            EmptyView()
        } else if adMobManager.isSdkInitialized {
            AdBannerRepresentable(viewWidth: viewWidth, isFailed: $isFailed, isLoaded: $isLoaded)
                .frame(height: isLoaded ? adHeight : 0)
                .opacity(isLoaded ? 1 : 0)
        } else {
            Color.clear.frame(height: 1)
        }
    }
}

// MARK: - Native Ad View (Yerel Gelişmiş)
class NativeAdViewModel: NSObject, ObservableObject, NativeAdLoaderDelegate {
    @Published var nativeAd: NativeAd?
    @Published var isFailed = false
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
        DispatchQueue.main.async {
            self.isFailed = true
        }
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
        // adChoicesView: Google'un zorunlu kıldığı attribution öğesi
        let adChoicesView = AdChoicesView()
        adChoicesView.translatesAutoresizingMaskIntoConstraints = false
        nativeAdView.addSubview(adChoicesView)
        nativeAdView.adChoicesView = adChoicesView
        NSLayoutConstraint.activate([
            adChoicesView.topAnchor.constraint(equalTo: nativeAdView.topAnchor, constant: 4),
            adChoicesView.trailingAnchor.constraint(equalTo: nativeAdView.trailingAnchor, constant: -4)
        ])
        
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
    @ObservedObject private var adMobManager = AdMobManager.shared
    // Native Advanced ID: ca-app-pub-9748717269838207/4478703611
    let adUnitID: String = "ca-app-pub-9748717269838207/4478703611"
    
    var body: some View {
        ZStack {
            if viewModel.isFailed {
                EmptyView()
            } else if let nativeAd = viewModel.nativeAd {
                NativeAdViewWrapper(nativeAd: nativeAd)
                    .frame(height: 140)
                    .glassEffect(in: .rect(cornerRadius: 20.0))
            } else {
                // Sadece yüklenirken kısa süreliğine boşluk bırakır
                Color.clear.frame(height: 1)
            }
        }
        .onAppear {
            if adMobManager.isSdkInitialized {
                viewModel.loadAd(adUnitID: adUnitID)
            }
        }
        .onChange(of: adMobManager.isSdkInitialized) { _, initialized in
            if initialized {
                viewModel.loadAd(adUnitID: adUnitID)
            }
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
