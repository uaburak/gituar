import SwiftUI
import StoreKit

// MARK: - ProView (paywall)

struct ProView: View {
    @ObservedObject private var pro = ProManager.shared
    @State private var showError = false

    private var priceText: String {
        pro.monthlyProduct?.displayPrice ?? "₺99,99"
    }

    var body: some View {
        // Sade, kaydırmasız: üstte başlık, ortada üç kısa madde, altta fiyat + buton + yasal metin
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            header
            Spacer(minLength: 24)
            benefits
            Spacer(minLength: 24)
            bottom
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pro.lastError) { _, newValue in
            showError = newValue != nil
        }
        .alert("İşlem Tamamlanamadı", isPresented: $showError) {
            Button("Tamam") { pro.lastError = nil }
        } message: {
            Text(pro.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(Color.accentColor)
            Text("Gituar Pro")
                .font(.system(size: 30, weight: .bold))
            Text("Reklamsız, kesintisiz çal.")
                .font(.system(size: 16))
                .foregroundColor(.secondary)
        }
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 18) {
            benefitRow(icon: "rectangle.slash", text: "Hiç reklam yok")
            benefitRow(icon: "icloud.and.arrow.down", text: "Çevrimdışı erişim: tüm şarkılar cihazında")
            benefitRow(icon: "globe", text: "gituar.com'da da reklamsız")
            benefitRow(icon: "heart", text: "Gituar'ın gelişmesine destek")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.accentColor)
                .frame(width: 26)
            Text(text)
                .font(.system(size: 16))
        }
    }

    private var bottom: some View {
        VStack(spacing: 14) {
            if pro.isPro {
                VStack(spacing: 4) {
                    Label("Pro aktif", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.green)
                    if let until = pro.expirationDate {
                        Text("Yenilenme: \(until.formatted(date: .long, time: .omitted))")
                            .font(.footnote).foregroundColor(.secondary)
                    } else if pro.isGifted {
                        Text(pro.giftUntil.map { "Hediye Pro · \($0.formatted(date: .long, time: .omitted)) tarihine kadar" } ?? "Hediye Pro · süresiz")
                            .font(.footnote).foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 6)
            } else {
                Button {
                    Task { await pro.purchase() }
                } label: {
                    HStack(spacing: 8) {
                        if pro.isPurchasing { ProgressView().tint(.white) }
                        Text("Pro'ya Geç · \(priceText)/ay")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(Color.accentColor, in: Capsule())
                }
                .disabled(pro.isPurchasing)

                Text("Aylık yenilenir, istediğin zaman iptal edebilirsin.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Button("Geri Yükle") { Task { await pro.restore() } }
                    .disabled(pro.isPurchasing)
                Text("·").foregroundColor(.secondary)
                NavigationLink("Koşullar") { TermsOfUseView() }
                Text("·").foregroundColor(.secondary)
                NavigationLink("Gizlilik") { PrivacyPolicyView() }
            }
            .font(.system(size: 13, weight: .medium))

            Text("Ödeme Apple hesabından alınır. Dönem bitiminden en az 24 saat önce iptal edilmezse abonelik aynı fiyattan yenilenir; App Store hesap ayarlarından yönetebilirsin.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
