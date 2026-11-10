import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    /// Açılış ekranı yalnızca uygulama ilk açılırken; giriş ekranı bir kez görüldükten sonra bir daha çıkmaz.
    @State private var launchFinished = false

    var body: some View {
        rootContent
            // "Tümünü indir" ilerlemesi: indirme bitene kadar her ekranda, alttaki arama/oynatma çubuğunun üstünde kalır
            .overlay(alignment: .bottom) { OfflineDownloadToast().padding(.bottom, 76) }
    }

    @ViewBuilder
    private var rootContent: some View {
        if !authViewModel.isInitialCheckDone {
            SplashView()
        } else {
            if authViewModel.isSignedIn {
                if authViewModel.isGuestMode || authViewModel.isProfileComplete {
                    MainView()
                        .onAppear { launchFinished = true }
                } else if authViewModel.isCheckingProfile {
                    // Profil kontrolü sürerken profil formunu gösterme (mevcut kullanıcıda form bir an görünüyordu).
                    // Açılışta açılış ekranı sürer; girişten sonra giriş ekranı yükleniyor göstergesiyle kalır.
                    if launchFinished {
                        AuthView()
                            .overlay {
                                ZStack {
                                    Color.black.opacity(0.15).ignoresSafeArea()
                                    ProgressView()
                                        .controlSize(.large)
                                        .padding(28)
                                        .glassEffect(in: .rect(cornerRadius: 24))
                                }
                            }
                    } else {
                        SplashView()
                    }
                } else if authViewModel.profileCheckFailed {
                    // Profil okunamadı (bağlantı) — profil formunu açıp mevcut profilin üzerine yazdırma
                    ProfileCheckFailedView()
                } else {
                    CompleteProfileView()
                }
            } else {
                AuthView()
                    .onAppear { launchFinished = true }
            }
        }
    }
}

/// Açılış ekranıyla (LaunchScreen.storyboard) birebir aynı: ortada logo ve ad; geçişte sıçrama olmaz.
struct SplashView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            VStack(spacing: 16) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 112, height: 112)
                Text("Gituar")
                    .font(.system(size: 28, weight: .bold))
            }
            // Storyboard'da logo ortanın 20 pt üstünde; yazıyla birlikte aynı yere oturur
            .offset(y: 5)
        }
    }
}

/// Açılışta profil bilgisi bağlantı hatası yüzünden alınamadığında gösterilir.
struct ProfileCheckFailedView: View {
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        ContentUnavailableView {
            Label("Bağlantı kurulamadı", systemImage: "wifi.exclamationmark")
        } description: {
            Text("Profil bilgilerin alınamadı. İnternet bağlantını kontrol edip tekrar dene.")
        } actions: {
            Button("Tekrar Dene") {
                authViewModel.refreshProfileIfNeeded()
            }
            .buttonStyle(.borderedProminent)

            Button("Çıkış Yap") {
                authViewModel.signOut()
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

struct MainView: View {
    @AppStorage("hasSeenOnboarding") var hasSeenOnboarding: Bool = false
    @State private var showOnboarding = false

    var body: some View {
        NavigationStack {
            HomeView()
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView()
        }
        .onAppear {
            if !hasSeenOnboarding {
                showOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ChordViewModel())
        .environmentObject(AuthViewModel())
}
