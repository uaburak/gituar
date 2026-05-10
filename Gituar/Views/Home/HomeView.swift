import SwiftUI
import FirebaseAuth
import Combine

struct HomeView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var navigateToProfile = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    
                    // Editor's Choice Banner
                    if !viewModel.editorRepertoires.isEmpty {
                        NavigationLink(destination: GenericRepertoireListView(title: "Editörün Seçimleri", repertoires: viewModel.editorRepertoires)) {
                            VStack(alignment: .leading, spacing: 14) {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.yellow)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Editörün Seçimleri")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                    Text("\(viewModel.editorRepertoires.count) Özel Liste")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.8))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                Image("EditorChoiceImage")
                                    .resizable()
                                    .scaledToFill()
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                            .glassEffect(in: .rect(cornerRadius: 20.0))
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Hero Section
                        HStack(spacing: 12) {
                            NavigationLink(destination: MySongsView()) {
                                MinimalCategoryCard(
                                    title: "Şarkılarım",
                                    subtitle: authViewModel.currentUser != nil ? "\(viewModel.userSongs(userId: authViewModel.currentUser!.uid).count) Kayıtlı" : "Giriş Yap",
                                    icon: "music.quarternote.3",
                                    color: .indigo
                                )
                            }
                            
                            NavigationLink(destination: RepertoireListView()) {
                                MinimalCategoryCard(
                                    title: "Repertuarlarım",
                                    subtitle: "Listeler",
                                    icon: "music.mic",
                                    color: .orange
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Action Row (Small Cards)
                        HStack(alignment: .top, spacing: 12) {
                            NavigationLink(destination: AllArtistsView()) {
                                HomeSmallCard(title: "Sanatçılar", icon: "person.2.fill")
                            }
                            
                            NavigationLink(destination: ExploreView()) {
                                HomeSmallCard(title: "Tüm Şarkılar", icon: "music.note.list")
                            }
                            
                            NavigationLink(destination: PopularChordsView()) {
                                HomeSmallCard(title: "Popüler", icon: "flame.fill")
                            }
                            
                            NavigationLink(destination: DiscoverView()) {
                                HomeSmallCard(title: "Keşfet", icon: "globe")
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Listeler
                        VStack(alignment: .leading, spacing: 12) {

                                
                            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
                            
                            LazyVGrid(columns: columns, spacing: 12) {
                                NavigationLink(destination: GenericSongListView(title: "Son Çalınanlar", songs: viewModel.recentlyPlayed)) {
                                    MinimalListCard(title: "Son Çalınanlar", icon: "clock.fill")
                                }
                                NavigationLink(destination: GenericSongListView(title: "Yeni Eklenenler", songs: viewModel.newArrivals)) {
                                    MinimalListCard(title: "Yeni Eklenenler", icon: "arrow.down.circle.fill")
                                }
                                NavigationLink(destination: GenericSongListView(title: "En Çok Eklenenler", songs: viewModel.mostAdded)) {
                                    MinimalListCard(title: "Çok Eklenenler", icon: "star.fill")
                                }
                                
                                if authViewModel.isAdmin {
                                    NavigationLink(destination: PendingApprovalListView()) {
                                        MinimalListCard(title: "Onay Bekleyenler", icon: "checkmark.seal.fill")
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        AdNativeView()
                            .padding(.horizontal, 20)
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 16)
            }
        }
        .background(Color(.systemBackground).ignoresSafeArea(.all, edges: .bottom))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $navigateToProfile) {
            ProfileSettingsView()
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                ZStack {
                    if let photoURL = authViewModel.currentUser?.photoURL {
                        AsyncImage(url: photoURL) { phase in
                            switch phase {
                            case .empty:
                                Circle().fill(Color(.systemGray5))
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                ZStack {
                                    Circle().fill(Color.accentColor.opacity(0.15))
                                    Text(authViewModel.userInitials)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            @unknown default:
                                Circle().fill(Color(.systemGray5))
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                            Text(authViewModel.userInitials)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                    }
                }
                .onTapGesture {
                    let impactMed = UIImpactFeedbackGenerator(style: .light)
                    impactMed.impactOccurred()
                    navigateToProfile = true
                }
            }
            
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            
            ToolbarItem(placement: .topBarLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hoş geldin, \(authViewModel.displayName.split(separator: " ").first ?? "")")
                        .font(.system(size: 16, weight: .bold))
                    Text("Bugün ne çalıyoruz?")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}
