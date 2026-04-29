import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        if authViewModel.isSignedIn {
            if authViewModel.isCheckingProfile {
                VStack {
                    ProgressView("Profil yükleniyor...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            } else if authViewModel.isGuestMode || authViewModel.isProfileComplete {
                MainView()
            } else {
                CompleteProfileView()
            }
        } else {
            AuthView()
        }
    }
}

struct MainView: View {
    var body: some View {
        NavigationStack {
            HomeView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ChordViewModel())
        .environmentObject(AuthViewModel())
}
