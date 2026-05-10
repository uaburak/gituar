import SwiftUI

struct GenericRepertoireListView: View {
    let title: String
    let repertoires: [Repertoire]
    
    var body: some View {
        Group {
            if repertoires.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.mic")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Bu listede henüz repertuar yok.")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]
                    
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(repertoires) { repertoire in
                            NavigationLink(destination: RepertoireDetailView(repertoire: repertoire)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repertoire.name)
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    
                                    Text("\(repertoire.songIds.count) Şarkı")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .glassEffect(in: .rect(cornerRadius: 20.0))
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
