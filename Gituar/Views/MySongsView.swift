import SwiftUI
import FirebaseAuth

struct MySongsView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    
    @State private var songToEdit: Song?
    @State private var navigateToNewSong = false
    
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
                        NavigationLink(destination: SongDetailView(song: song, playlist: userSongs)) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(song.songName)
                                        .font(.system(size: 16, weight: .semibold))
                                    
                                    Spacer()
                                    
                                    if song.status == "pending" {
                                        StatusBadge(text: "Onay Bekliyor", color: .orange, icon: nil)
                                    } else if song.status == "approved" {
                                        StatusBadge(text: "Yayında", color: .green, icon: nil)
                                    } else if song.status == "rejected" {
                                        StatusBadge(text: "Reddedildi", color: .red, icon: nil)
                                    } else {
                                        StatusBadge(text: "Taslak", color: .gray, icon: nil)
                                    }
                                }
                                Text(song.artist)
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                viewModel.deleteSong(song)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                            
                            Button {
                                songToEdit = song
                            } label: {
                                Label("Düzenle", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                    }
                    .listStyle(.plain)
                }
            } else {
                Text("Şarkılarınızı görmek için giriş yapmalısınız.")
            }
        }
        .navigationTitle("Şarkılarım")
        .navigationDestination(isPresented: $navigateToNewSong) {
            EditSongView(song: nil)
        }
        .navigationDestination(item: $songToEdit) { song in
            EditSongView(song: song)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: {
                    navigateToNewSong = true
                }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

struct StatusBadge: View {
    let text: String
    let color: Color
    var icon: String? = nil
    
    var body: some View {
        HStack(spacing: 4) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }
}

struct EditSongView: View {
    @EnvironmentObject var viewModel: ChordViewModel
    @EnvironmentObject var authViewModel: AuthViewModel
    @Environment(\.dismiss) var dismiss
    
    let song: Song?
    
    @State private var songName: String = ""
    @State private var artist: String = ""
    @State private var originalKey: String = "C"
    @State private var content: String = ""
    @State private var status: String = "draft"
    
    private let allNotes = ["C", "C#", "Db", "D", "D#", "Eb", "E", "F", "F#", "Gb", "G", "G#", "Ab", "A", "A#", "Bb", "B"]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Image or Icon
                VStack(spacing: 8) {
                    Image(systemName: "guitars.fill")
                        .font(.system(size: 50))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 16)
                    
                    Text(song == nil ? "Yeni Şarkı Oluştur" : "Şarkıyı Düzenle")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(song == nil ? "Şarkının sözlerini ve akorlarını aşağıya ekle." : "Şarkında yapmak istediğin değişiklikleri yap.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    formField(text: $songName, placeholder: "Şarkı Adı")
                    
                    HStack(spacing: 16) {
                        formField(text: $artist, placeholder: "Sanatçı")
                        
                        Menu {
                            ForEach(allNotes, id: \.self) { note in
                                Button {
                                    originalKey = note
                                } label: {
                                    Text(note)
                                }
                            }
                        } label: {
                            HStack {
                                Text(originalKey)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.up.chevron.down")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding()
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                        }
                        .frame(width: 90)
                    }
                    
                    // Text Editor
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $content)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .padding(8)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        
                        if content.isEmpty {
                            Text("Akorları ve sözleri buraya yazın...\n\nÖrnek:\nAm         G\nBu bir şarkı sözü...")
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundColor(Color(.placeholderText))
                                .padding(.horizontal, 12)
                                .padding(.top, 16)
                                .allowsHitTesting(false)
                        }
                    }
                    .frame(minHeight: 250)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color(.separator), lineWidth: 1))
                }
                .padding(.horizontal, 24)
                
                // Status Badges
                if status == "pending" {
                    StatusBadge(text: "Şarkınız onay bekliyor", color: .orange, icon: "clock.fill")
                } else if status == "approved" {
                    StatusBadge(text: "Şarkınız yayında", color: .green, icon: "checkmark.seal.fill")
                } else if status == "rejected" {
                    StatusBadge(text: "Reddedildi. Lütfen düzenleyip tekrar gönderin.", color: .red, icon: "xmark.octagon.fill")
                }
                
                // Actions
                HStack(spacing: 12) {
                    Button {
                        saveSong(asStatus: status == "approved" ? "approved" : "draft")
                    } label: {
                        Text("Taslak Kaydet")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
                    }
                    
                    if status != "pending" && status != "approved" {
                        Button {
                            saveSong(asStatus: "pending")
                        } label: {
                            Text("Yayınla")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(Color.accentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .navigationTitle(song == nil ? "Yeni Şarkı" : "Düzenle")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let song = song, let url = URL(string: "gituar://song/\(song.docId)") {
                    ShareLink(item: url, message: Text("\(song.artist) - \(song.songName) şarkısına Gituar'dan göz at!")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .onAppear {
            if let song = song {
                songName = song.songName
                artist = song.artist
                originalKey = song.originalKey
                content = song.content
                status = song.status ?? "draft"
            }
        }
    }
    
    private func formField(text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color(.separator), lineWidth: 1))
    }
    
    private func saveSong(asStatus targetStatus: String) {
        guard let userId = authViewModel.currentUser?.uid else { return }
        
        let songToSave = Song(
            id: song?.id,
            docId: song?.docId ?? UUID().uuidString,
            artist: artist.trimmingCharacters(in: .whitespaces),
            songName: songName.trimmingCharacters(in: .whitespaces),
            originalKey: originalKey,
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: song?.createdAt ?? Date(),
            totalViews: song?.totalViews ?? 0,
            recentViews: song?.recentViews ?? 0,
            repertoireAdds: song?.repertoireAdds ?? 0,
            ownerId: userId,
            status: targetStatus
        )
        
        viewModel.saveSong(songToSave)
        dismiss()
    }
}
