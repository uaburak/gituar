import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        if !authViewModel.isInitialCheckDone {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                ProgressView()
                    .tint(.gray)
            }
        } else {
            if authViewModel.isSignedIn {
                if authViewModel.isGuestMode || authViewModel.isProfileComplete {
                    MainView()
                } else if authViewModel.isCheckingProfile {
                    // Profil kontrolü sürerken profil formunu gösterme (mevcut kullanıcıda form bir an görünüyordu)
                    ProgressView()
                        .tint(.gray)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).ignoresSafeArea())
                } else if authViewModel.profileCheckFailed {
                    // Profil okunamadı (bağlantı) — profil formunu açıp mevcut profilin üzerine yazdırma
                    ProfileCheckFailedView()
                } else {
                    CompleteProfileView()
                }
            } else {
                AuthView()
            }
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
