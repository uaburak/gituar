import SwiftUI
import Combine
import Foundation
import FirebaseAuth

struct ProfileSettingsView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    
    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
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
                                    Circle().fill(Color.accentColor.opacity(0.1))
                                    Text(authViewModel.userInitials)
                                        .font(.system(size: 24, weight: .bold))
                                        .foregroundColor(.accentColor)
                                }
                            @unknown default:
                                Circle().fill(Color(.systemGray5))
                            }
                        }
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                            Text(authViewModel.userInitials)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.accentColor)
                        }
                        .frame(width: 60, height: 60)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(authViewModel.displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text(authViewModel.userEmail)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Section(header: Text("İçeriklerim")) {
                NavigationLink(destination: MySongsView()) {
                    Label("Şarkılarım", systemImage: "music.note.list")
                }
                
                NavigationLink(destination: SongNotesView()) {
                    Label("Şarkı Notlarım", systemImage: "note.text")
                }
            }
            
            Section {
                Button(role: .destructive) {
                    authViewModel.signOut()
                } label: {
                    HStack {
                        Spacer()
                        Text("Çıkış Yap")
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Profil")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notes Feature

struct SongNote: Identifiable, Codable {
    var id = UUID()
    var songTitle: String
    var noteText: String
    var createdAt: Date
}

class NotesViewModel: ObservableObject {
    @Published var notes: [SongNote] = []
    private let notesKey = "user_song_notes"
    
    init() {
        loadNotes()
    }
    
    func loadNotes() {
        if let data = UserDefaults.standard.data(forKey: notesKey),
           let saved = try? JSONDecoder().decode([SongNote].self, from: data) {
            self.notes = saved
        }
    }
    
    func saveNotes() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: notesKey)
        }
    }
    
    func addNote(songTitle: String, noteText: String) {
        let note = SongNote(songTitle: songTitle, noteText: noteText, createdAt: Date())
        notes.insert(note, at: 0)
        saveNotes()
    }
    
    func deleteNote(at offsets: IndexSet) {
        notes.remove(atOffsets: offsets)
        saveNotes()
    }
}

struct SongNotesView: View {
    @StateObject private var notesVM = NotesViewModel()
    @State private var showingAddNote = false
    
    var body: some View {
        Group {
            if notesVM.notes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "note.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Henüz hiç not eklemedin.")
                        .font(.headline)
                    Text("Şarkılar için aldığın kişisel notlar burada listelenir.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            } else {
                List {
                    ForEach(notesVM.notes) { note in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(note.songTitle)
                                .font(.headline)
                            Text(note.noteText)
                                .font(.body)
                                .foregroundColor(.secondary)
                            Text(note.createdAt.formatted(.dateTime.day().month().year().hour().minute()))
                                .font(.caption2)
                                .foregroundColor(Color(.tertiaryLabel))
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: notesVM.deleteNote)
                }
            }
        }
        .navigationTitle("Şarkı Notlarım")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddNote = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddNote) {
            AddNoteView(notesVM: notesVM)
        }
    }
}

struct AddNoteView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var notesVM: NotesViewModel
    
    @State private var songTitle = ""
    @State private var noteText = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Şarkı Bilgisi")) {
                    TextField("Hangi şarkı için?", text: $songTitle)
                }
                
                Section(header: Text("Notun")) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 150)
                }
            }
            .navigationTitle("Yeni Not")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        notesVM.addNote(songTitle: songTitle, noteText: noteText)
                        dismiss()
                    }
                    .disabled(songTitle.isEmpty || noteText.isEmpty)
                }
            }
        }
    }
}
