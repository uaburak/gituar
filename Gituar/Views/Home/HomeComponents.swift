import SwiftUI

struct MinimalCategoryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(in: .rect(cornerRadius: 20.0))
    }
}

struct MinimalListCard: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(.primary)
                .frame(width: 24)
            
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(in: .rect(cornerRadius: 20.0))
    }
}

struct SongRowCard: View {
    let song: Song
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                Text(song.songName.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(song.songName)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(song.originalKey)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

/// Sanatçı listesi satırı — AllArtistsView ve ana sayfa aramasında ortak.
struct ArtistRowCard: View {
    let artist: String
    let songCount: Int

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(width: 48, height: 48)
                Text(artist.prefix(1).uppercased())
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(artist)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text("\(songCount) Şarkı")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            // List, NavigationLink satırına kendi okunu ekler — ayrıca chevron çizme (çift ok oluyordu)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
