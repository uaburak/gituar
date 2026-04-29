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
        .navigationTitle("İletişim ve Yasal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TermsOfUseView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Kullanım Şartları")
                    .font(.title2)
                    .bold()
                
                Text("Gituar uygulamasını kullanarak aşağıdaki şartları kabul etmiş sayılırsınız.")
                
                Text("1. İçerik ve Telif Hakkı")
                    .font(.headline)
                Text("Uygulama içerisindeki akor, söz ve tablar müzik eğitimi amacıyla paylaşılmaktadır. Tüm eserlerin telif hakları kendi sahiplerine aittir. Telif hakkı ihlali olduğunu düşündüğünüz içerikler için iletişim adresimizden bize ulaşabilirsiniz; ilgili içerik en kısa sürede incelenip kaldırılacaktır.")
                
                Text("2. Kullanıcı Sorumluluğu")
                    .font(.headline)
                Text("Kullanıcılar uygulamayı yasalara uygun bir şekilde kullanmakla yükümlüdür. Uygulama altyapısına zarar verecek veya tersine mühendislik oluşturacak girişimler yasaktır.")
                
                Text("3. Değişiklikler")
                    .font(.headline)
                Text("Gituar, kullanım şartlarında önceden haber vermeksizin değişiklik yapma hakkını saklı tutar.")
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Kullanım Şartları")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Gizlilik ve Çerez Politikası")
                    .font(.title2)
                    .bold()
                
                Text("Kullanıcılarımızın gizliliğine önem veriyoruz. Bu politika, Gituar uygulamasını kullanırken toplanan verileri açıklar.")
                
                Text("1. Toplanan Veriler")
                    .font(.headline)
                Text("Uygulama deneyiminizi iyileştirmek amacıyla temel kullanım verileri (görüntülenen şarkılar vb.) cihazınızda veya bulut sistemimizde güvenli bir şekilde saklanabilir.")
                
                Text("2. Çerezler ve Yerel Depolama")
                    .font(.headline)
                Text("Uygulamamız, kişiselleştirilmiş ayarlarınızı (yazı boyutu, tema, ton tercihleri vb.) hatırlamak için cihazınızın yerel depolama özelliklerini (UserDefaults, AppStorage vb.) kullanır.")
                
                Text("3. Veri Güvenliği ve Paylaşım")
                    .font(.headline)
                Text("Kişisel verileriniz güvenli sunucularda saklanmakta olup, yasal zorunluluklar haricinde üçüncü şahıslarla reklam amacıyla izinsiz paylaşılmaz.")
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Gizlilik Politikası")
        .navigationBarTitleDisplayMode(.inline)
    }
}
