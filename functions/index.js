const { onSchedule } = require("firebase-functions/v2/scheduler");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

// Bu fonksiyon her gece saat 03:00'te (Istanbul saati) otomatik çalışır
exports.aggregateMetrics = onSchedule({
    schedule: "every day 03:00",
    timeZone: "Europe/Istanbul"
}, async (event) => {
    try {
        console.log("Metrikleri toplama işlemi başlatıldı...");
        
        // 1. Tüm song-metrics belgelerini çek
        const metricsSnapshot = await db.collection("song-metrics").get();
        
        const aggregatedData = {};
        
        metricsSnapshot.forEach((doc) => {
            const data = doc.data();
            const totalViews = data.totalViews || 0;
            const recentViews = data.recentViews || 0;
            const repAdds = data.repertoireAdds || 0;
            
            // Format: "sarki_id": [totalViews, recentViews, repertoireAdds]
            aggregatedData[doc.id] = [totalViews, recentViews, repAdds];
        });
        
        // 2. Hepsini tek bir dosyaya (popularity_registry) yaz
        await db.collection("metadata").doc("popularity_registry").set({
            metrics: aggregatedData
        });
        
        console.log(`Başarılı! ${metricsSnapshot.size} adet şarkının metriği tek bir dosyaya sıkıştırıldı.`);
    } catch (error) {
        console.error("Metrik toplama sırasında hata oluştu:", error);
    }
});
