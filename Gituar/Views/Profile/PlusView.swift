import SwiftUI
import StoreKit

// MARK: - PlusView (paywall)

struct PlusView: View {
    @ObservedObject private var plus = PlusManager.shared
    @State private var showError = false

    private var priceText: String {
        plus.monthlyProduct?.displayPrice ?? "₺99"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header
                benefits
                priceCard
                actions
                legal
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Gituar Plus")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: plus.lastError) { _, newValue in
            showError = newValue != nil
        }
        .alert("İşlem Tamamlanamadı", isPresented: $showError) {
            Button("Tamam") { plus.lastError = nil }
        } message: {
            Text(plus.lastError ?? "")
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "sparkles")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            Text("Gituar Plus")
                .font(.system(size: 28, weight: .bold))
            Text("Reklamsız, kesintisiz çal.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 8)
    }

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 14) {
            benefitRow(icon: "rectangle.slash", title: "Reklamsız kullanım", detail: "Banner, geçiş ve açılış reklamlarının hiçbiri gösterilmez.")
            benefitRow(icon: "globe", title: "Web'de de geçerli", detail: "Aynı hesapla gituar web sitesine girince orada da reklam çıkmaz.")
            benefitRow(icon: "heart.fill", title: "Geliştirmeye destek", detail: "Yeni akorlar ve özellikler için bize güç verirsin.")
        }
        .padding(18)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func benefitRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundColor(.secondary)
            }
        }
    }

    private var priceCard: some View {
        VStack(spacing: 6) {
            if plus.isPlus {
                Label("Plus aktif", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.green)
                if let until = plus.expirationDate {
                    Text("Yenilenme: \(until.formatted(date: .long, time: .omitted))")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(priceText)
                        .font(.system(size: 34, weight: .bold))
                    Text("/ ay")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                Text("Aylık yenilenir, istediğin zaman iptal edebilirsin.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if !plus.isPlus {
                Button {
                    Task { await plus.purchase() }
                } label: {
                    HStack(spacing: 8) {
                        if plus.isPurchasing { ProgressView().tint(.white) }
                        Text("Plus'a Geç · \(priceText)/ay")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .disabled(plus.isPurchasing)
            }

            Button {
                Task { await plus.restore() }
            } label: {
                Text("Satın Alımları Geri Yükle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .disabled(plus.isPurchasing)
        }
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Text("Ödeme, satın alma onayında Apple Kimliği hesabından alınır. Abonelik, dönem bitiminden en az 24 saat önce iptal edilmediği sürece aynı fiyattan otomatik yenilenir. Aboneliğini App Store hesap ayarlarından yönetebilir ve iptal edebilirsin.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                NavigationLink("Kullanım Koşulları") { TermsOfUseView() }
                NavigationLink("Gizlilik Politikası") { PrivacyPolicyView() }
            }
            .font(.caption)
        }
        .padding(.bottom, 20)
    }
}
