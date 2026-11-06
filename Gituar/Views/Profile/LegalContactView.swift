import SwiftUI

struct LegalContactView: View {
    var body: some View {
        List {
            Section(header: Text("İletişim")) {
                Button(action: {
                    if let url = URL(string: "mailto:iletisim@gituar.com") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack {
                        Image(systemName: "envelope.fill")
                            .foregroundColor(.blue)
                        Text("iletisim@gituar.com")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Section(header: Text("Yasal Bilgiler")) {
                NavigationLink(destination: TermsOfUseView()) {
                    Text("Kullanım Şartları")
                }
                
                NavigationLink(destination: PrivacyPolicyView()) {
                    Text("Gizlilik ve Çerez Politikası")
                }
            }
        }
        .scrollEdgeEffectStyle(.soft)
        .navigationTitle("İletişim ve Yasal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Yasal metin bölümü: başlık + paragraflar.
private struct LegalSection: View {
    let title: String
    let paragraphs: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ForEach(paragraphs, id: \.self) { Text($0).font(.subheadline) }
        }
    }
}

// Web'deki /kullanim-sartlari/ ve /gizlilik/ sayfalarıyla aynı içerik.
struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Gituar'ı (uygulama ve gituar.com) kullanarak aşağıdaki şartları kabul etmiş sayılırsın. Son güncelleme: 6 Kasım 2026.")
                    .foregroundStyle(.secondary)
                LegalSection(title: "1. İçerik ve telif hakları", paragraphs: [
                    "Gituar'daki akorları ve sözleri kullanıcılar ekler; içerikler müzik eğitimi amacıyla yayımlanır. Eserlerin tüm hakları sahiplerine aittir.",
                    "Bir içeriğin telif hakkını ihlal ettiğini düşünüyorsan şarkı sayfasındaki \"Şikayet Et\" ile ya da iletisim@gituar.com adresinden bildir. Geçerli bildirimler en geç 48 saat içinde yayından kaldırılır.",
                    "İçeriklerin doğruluğu garanti edilmez; akorlar hata içerebilir.",
                ])
                LegalSection(title: "2. Kullanıcı içerikleri ve sıfır tolerans", paragraphs: [
                    "Paylaştığın akor, söz, repertuar ve bildirimlerden sen sorumlusun. Uygunsuz içeriğe ve kötüye kullanan kullanıcılara sıfır tolerans uygulanır: küfür, hakaret, nefret söylemi, taciz, müstehcenlik ve suç teşkil eden içerik yasaktır.",
                    "Gönderilen içerikler otomatik filtreden ve editör onayından geçtikten sonra yayımlanır. Şikayet edilen içerikler 24 saat içinde incelenir; kuralları ihlal eden içerik kaldırılır ve hesap kapatılabilir.",
                    "Rahatsız olduğun kullanıcıyı şarkı sayfasındaki \"Engelle\" ile engelleyebilirsin; engellediğin kişinin içerikleri sana gösterilmez.",
                ])
                LegalSection(title: "3. Hesap", paragraphs: [
                    "Apple, Google ya da e-posta ile giriş yapabilirsin. Hesabını ve verilerini Profil > Ayarlar'dan istediğin zaman silebilirsin.",
                ])
                LegalSection(title: "4. Gituar Pro", paragraphs: [
                    "Gituar Pro, reklamsız kullanım sunan aylık otomatik yenilenen bir aboneliktir ve App Store üzerinden satın alınır. Ödeme, satın alma onayında Apple hesabından alınır. Abonelik, dönem bitiminden en az 24 saat önce iptal edilmezse aynı ücretle yenilenir. Aboneliği App Store hesap ayarlarından yönetebilir ve iptal edebilirsin.",
                ])
                LegalSection(title: "5. Kullanım kuralları", paragraphs: [
                    "İçeriklerin izinsiz ticari amaçla ya da otomatik araçlarla toplu kopyalanması, altyapıya zarar verecek girişimler ve tersine mühendislik yasaktır.",
                ])
                LegalSection(title: "6. Değişiklikler ve uygulanacak hukuk", paragraphs: [
                    "Bu şartları gerektiğinde güncelleyebiliriz. Şartlara Türk hukuku uygulanır; uyuşmazlıklarda İstanbul mahkemeleri yetkilidir. Sorular için: iletisim@gituar.com",
                ])
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft)
        .navigationTitle("Kullanım Şartları")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Bu politika, Gituar uygulamasını ve gituar.com'u kullanırken hangi verilerin işlendiğini açıklar (6698 sayılı KVKK). Son güncelleme: 6 Kasım 2026.")
                    .foregroundStyle(.secondary)
                LegalSection(title: "Hangi verileri işliyoruz?", paragraphs: [
                    "Hesap bilgileri: Apple, Google ya da e-posta ile giriş yaptığında adın, e-posta adresin ve varsa profil fotoğrafın (Google Firebase Authentication).",
                    "Kullanım verileri: favorilerin, repertuarların, şarkı başına ton ve kapo ayarların, gönderdiğin akorlar, şikayetlerin ve engellediğin kullanıcılar (Google Cloud Firestore).",
                    "Abonelik durumu: Gituar Pro'nun aktif olup olmadığı. Ödeme bilgilerin Apple'da kalır.",
                    "Giriş yapmadan da kullanabilirsin; bu durumda hesap verisi oluşmaz.",
                ])
                LegalSection(title: "Reklamlar", paragraphs: [
                    "Pro kullanmayanlara Google AdMob reklamları gösterilir. Uygulama, reklam kimliğini (IDFA) kullanmak için iOS'un izin penceresiyle onayını ister; izin vermezsen kişiselleştirilmemiş reklam gösterilir.",
                ])
                LegalSection(title: "Cihazda saklananlar", paragraphs: [
                    "Tema, yazı boyutu, son çalınanlar ve ton tercihlerin cihazında saklanır.",
                ])
                LegalSection(title: "Paylaşım ve saklama", paragraphs: [
                    "Hizmet sağlayıcılarımız Google (Firebase, AdMob) ve Apple'dır; veriler yalnızca hizmetin sunulması için aktarılır, satılmaz. Hesabını sildiğinde verilerin silinir.",
                ])
                LegalSection(title: "Hakların", paragraphs: [
                    "Verilerine erişme, düzeltme, silme ve itiraz hakların var. Taleplerin için iletisim@gituar.com adresine yaz; en geç 30 gün içinde yanıt veririz. Gituar 13 yaşın altındaki çocuklara yönelik değildir.",
                ])
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft)
        .navigationTitle("Gizlilik ve Çerez Politikası")
        .navigationBarTitleDisplayMode(.inline)
    }
}
