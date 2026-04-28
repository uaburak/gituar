import UIKit
import SwiftUI
import Combine

// MARK: - AutoScroller
class AutoScroller: ObservableObject {
    weak var scrollView: UIScrollView?
    private var displayLink: CADisplayLink?
    
    // Yüksek hassasiyetli pozisyon takibi
    private var exactY: CGFloat? = nil
    private var lastTimestamp: CFTimeInterval = 0

    // İstediğiniz kadar düşürebilirsiniz (örn: 5)
    var pixelsPerSecond: CGFloat = 12
    
    // Scroll bittiğinde çağrılacak closure
    var onFinish: (() -> Void)?

    func start() {
        guard displayLink == nil else { return }
        lastTimestamp = 0
        exactY = nil
        displayLink = CADisplayLink(target: self, selector: #selector(tick(_:)))
        displayLink?.add(to: .main, forMode: .common)
    }

    func pause() {
        displayLink?.invalidate()
        displayLink = nil
    }

    func reset(animated: Bool = true) {
        pause()
        exactY = nil
        DispatchQueue.main.async { [weak self] in
            self?.scrollView?.setContentOffset(.zero, animated: animated)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        guard
            let sv = scrollView,
            sv.frame.height > 0,
            sv.contentSize.height > sv.frame.height
        else { return }
        
        // İlk frame için timestamp başlat
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }
        
        // Geçen zaman (saniye) x Hız (pixel/saniye)
        let dt = link.timestamp - lastTimestamp
        lastTimestamp = link.timestamp
        let delta = pixelsPerSecond * CGFloat(dt)

        let maxY = sv.contentSize.height - sv.frame.height + sv.contentInset.bottom
        let currentY = sv.contentOffset.y
        
        // Eğer UIKit değeri bizim değerimizden çok farklıysa (kullanıcı parmağıyla kaydırdıysa) senkronize et
        if exactY == nil || abs(exactY! - currentY) > 1.0 {
            exactY = currentY
        }
        
        exactY! += delta

        if exactY! >= maxY {
            sv.setContentOffset(CGPoint(x: 0, y: maxY), animated: false)
            pause()
            DispatchQueue.main.async { [weak self] in
                self?.onFinish?()
            }
        } else {
            // Animated = false sayesinde pürüzsüz kayar
            sv.setContentOffset(CGPoint(x: 0, y: exactY!), animated: false)
        }
    }
}

// MARK: - ScrollViewFinder
struct ScrollViewFinder: UIViewRepresentable {
    let onFound: (UIScrollView) -> Void

    func makeUIView(context: Context) -> _FinderView {
        _FinderView(onFound: onFound)
    }
    func updateUIView(_ uiView: _FinderView, context: Context) {}

    class _FinderView: UIView {
        let onFound: (UIScrollView) -> Void
        private var didFire = false

        init(onFound: @escaping (UIScrollView) -> Void) {
            self.onFound = onFound
            super.init(frame: .zero)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }
        required init?(coder: NSCoder) { fatalError() }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard !didFire, window != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.findScrollView()
            }
        }

        private func findScrollView() {
            var view: UIView? = superview
            while let v = view {
                if let sv = v as? UIScrollView,
                   sv.isScrollEnabled,
                   sv.alwaysBounceVertical || sv.contentSize.height > 0 {
                    didFire = true
                    onFound(sv)
                    return
                }
                view = v.superview
            }
        }
    }
}
