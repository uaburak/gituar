import SwiftUI

struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let iconName: String
    let color: Color
}

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var currentStep = 0
    @State private var isFloating = false
    @Environment(\.dismiss) var dismiss
    
    let steps = [
        OnboardingStep(title: "Gituar'a Hoş Geldin!", description: "Binlerce şarkının akor ve sözlerine anında ulaş, müziğin keyfini çıkar.", iconName: "music.note.house.fill", color: .blue),
        OnboardingStep(title: "Geniş Arşiv", description: "Sürekli güncellenen popüler ve güncel şarkı havuzumuzda dilediğini ara.", iconName: "magnifyingglass", color: .orange),
        OnboardingStep(title: "Kendi Repertuvarın", description: "Beğendiğin şarkıları kendi listene ekle, sahnede veya arkadaş ortamında hemen çal.", iconName: "star.fill", color: .yellow),
        OnboardingStep(title: "Popülerlik Puanı", description: "Hangi şarkıların daha çok çalındığını gör, trendleri yakala.", iconName: "chart.line.uptrend.xyaxis", color: .green),
        OnboardingStep(title: "Çevrimdışı Erişim", description: "Şarkıları bir kez açman yeterli. İnternetin olmasa bile her an seninle.", iconName: "icloud.and.arrow.down.fill", color: .purple),
        OnboardingStep(title: "Hazırsan Başlayalım!", description: "Hemen favori şarkılarını bul ve çalmaya başla.", iconName: "guitars.fill", color: .red)
    ]
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground).ignoresSafeArea()
            
            VStack(spacing: 0) {
                TabView(selection: $currentStep) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        VStack(spacing: 40) {
                            Spacer()
                            
                            // Opaklık Değiştirmeyen, Sürekli ve Yavaş Animasyonlu İkon
                            Image(systemName: steps[index].iconName)
                                .font(.system(size: 110))
                                .foregroundStyle(steps[index].color)
                                // 1. Native Zıplama (Sürekli ve Çok Yavaş)
                                .symbolEffect(.bounce.up.byLayer, options: .repeating.speed(0.1))
                                // 2. Sürekli Süzülme (Opaklık Sabit)
                                .offset(y: isFloating ? -8 : 8)
                            
                            VStack(spacing: 20) {
                                Text(steps[index].title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.center)
                                
                                Text(steps[index].description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 48)
                                    .lineSpacing(6)
                            }
                            
                            Spacer()
                            Spacer()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.5), value: currentStep)
                
                // Sayfa İndikatörü
                HStack(spacing: 10) {
                    ForEach(0..<steps.count, id: \.self) { index in
                        Capsule()
                            .fill(currentStep == index ? Color.accentColor : Color.accentColor.opacity(0.2))
                            .frame(width: currentStep == index ? 24 : 8, height: 8)
                    }
                }
                .padding(.bottom, 40)
                
                // Ana Buton
                Button(action: {
                    if currentStep < steps.count - 1 {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            currentStep += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                }) {
                    Text(currentStep == steps.count - 1 ? "Hadi Başlayalım" : "Devam Et")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.accentColor)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            // İkonların süzülme animasyonunu başlat
            withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                isFloating = true
            }
        }
    }
    
    private func completeOnboarding() {
        withAnimation(.easeInOut(duration: 0.4)) {
            hasSeenOnboarding = true
            dismiss()
        }
    }
}

#Preview {
    OnboardingView()
}
