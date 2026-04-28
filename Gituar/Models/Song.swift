import Foundation
import FirebaseFirestore

struct Song: Identifiable, Codable {
    @DocumentID var id: String?
    var docId: String
    var artist: String
    var songName: String
    var originalKey: String
    var content: String
    var createdAt: Date?
    
    // Metrikler
    var totalViews: Int?
    var recentViews: Int?
    var repertoireAdds: Int?
    
    // Sahiplik
    var ownerId: String?
    
    
    // Popülerlik Puanı Algoritması
    // Formula: (TotalViews * 0.1) + (RecentViews * 0.6) + (RepertoireAdds * 0.3)
    var popularityScore: Double {
        let wTotal = 0.1
        let wRecent = 0.6
        let wAdds = 0.3
        
        let total = Double(totalViews ?? 0)
        let recent = Double(recentViews ?? 0)
        let adds = Double(repertoireAdds ?? 0)
        
        return (total * wTotal) + (recent * wRecent) + (adds * wAdds)
    }
}


