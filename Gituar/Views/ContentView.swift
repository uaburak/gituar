import SwiftUI

struct ContentView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    var body: some View {
        if authViewModel.isSignedIn {
            MainView()
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
