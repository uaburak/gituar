import SwiftUI

// MARK: - Katalog / liste durum görünümleri
//
// Şarkı listelerinin ortak "yükleniyor", "yüklenemedi" ve "sonuç yok" halleri.

/// Resmi şarkı kataloğu Storage'dan inerken gösterilen spinner.
struct CatalogLoadingView: View {
    var text: String = "Şarkılar yükleniyor…"

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Katalog indirilemediğinde (ör. ilk açılışta internet yokken) gösterilir.
struct CatalogLoadFailedView: View {
    @EnvironmentObject var chordsManager: ChordsStorageManager

    var body: some View {
        ContentUnavailableView {
            Label("Şarkılar yüklenemedi", systemImage: "wifi.exclamationmark")
        } description: {
            Text("İnternet bağlantını kontrol edip tekrar dene.")
        } actions: {
            Button("Tekrar Dene") {
                chordsManager.retryIfFailed()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Arama hiçbir sonuç döndürmediğinde listenin üzerine bindirilir.
struct NoSearchResultsView: View {
    let query: String

    var body: some View {
        ContentUnavailableView(
            "Sonuç bulunamadı",
            systemImage: "magnifyingglass",
            description: Text("“\(query)” için eşleşen bir şey yok.")
        )
    }
}
