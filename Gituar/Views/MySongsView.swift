import SwiftUI
import FirebaseAuth

struct MySongsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        Group {
            if let userId = authViewModel.currentUser?.uid {
                let userSongs = viewModel.userSongs(userId: userId)
                
                if userSongs.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Henüz kendi şarkını oluşturmadın.")
                            .font(.headline)
                        Text("Kendi şarkılarını ve akorlarını ekleyerek burada listeleyebilirsin.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    List(userSongs, id: \.docId) { song in
                        NavigationLink(destination: EditSongView(song: song)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(song.songName)
                                    .font(.system(size: 16, weight: .semibold))
                                Text(song.artist)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                Text("Şarkılarınızı görmek için giriş yapmalısınız.")
            }
        }
        .navigationTitle("Şarkılarım")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: EditSongView(song: nil)) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct EditSongView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    let song: Song?
    
    @State private var songName: String = ""
    @State private var artist: String = ""
    @State private var originalKey: String = ""
    @State private var content: String = ""
    
    var body: some View {
        Form {
            Section(header: Text("Şarkı Bilgileri")) {
                TextField("Şarkı Adı", text: $songName)
                TextField("Sanatçı", text: $artist)
                TextField("Orijinal Ton", text: $originalKey)
            }
            
            Section(header: Text("Akorlar ve Sözler")) {
                TextEditor(text: $content)
                    .frame(minHeight: 200)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle(song == nil ? "Yeni Şarkı" : "Şarkıyı Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Kaydet") {
                    saveSong()
                }
                .disabled(songName.isEmpty || artist.isEmpty || content.isEmpty)
            }
        }
        .onAppear {
            if let song = song {
                songName = song.songName
                artist = song.artist
                originalKey = song.originalKey
                content = song.content
            }
        }
    }
    
    private func saveSong() {
        guard let userId = authViewModel.currentUser?.uid else { return }
        
        let songToSave = Song(
            id: song?.id,
            docId: song?.docId ?? UUID().uuidString,
            artist: artist,
            songName: songName,
            originalKey: originalKey,
            content: content,
            createdAt: song?.createdAt ?? Date(),
            totalViews: song?.totalViews ?? 0,
            recentViews: song?.recentViews ?? 0,
            repertoireAdds: song?.repertoireAdds ?? 0,
            ownerId: userId
        )
        
        viewModel.saveSong(songToSave)
        dismiss()
    }
}
