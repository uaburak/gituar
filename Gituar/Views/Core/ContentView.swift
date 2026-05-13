import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        if !authViewModel.isInitialCheckDone {
            ZStack {
                Color.white.ignoresSafeArea()
                ProgressView()
                    .tint(.gray)
            }
        } else {
            if authViewModel.isSignedIn {
                if authViewModel.isGuestMode || authViewModel.isProfileComplete {
                    MainView()
                } else {
                    CompleteProfileView()
                }
            } else {
                AuthView()
            }
        }
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
