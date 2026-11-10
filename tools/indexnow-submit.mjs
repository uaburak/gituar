// Bütün site haritasını IndexNow'a (Bing, Yandex, Seznam, Naver) bir kez bildirir.
// Kullanım (web ve anahtar dosyası yayındayken): node tools/indexnow-submit.mjs
// Sonrasında yeni/değişen şarkıları API kendisi bildirir (api/src/index.ts → notifyIndexNow).
const SITE = "https://gituar.com";
const KEY = "68ad4424d5cfece8fed64cd8fceac050";
const UA = { "User-Agent": "Mozilla/5.0 (Gituar IndexNow)" };

const index = await (await fetch(`${SITE}/sitemap-index.xml`, { headers: UA })).text();
const parts = [...index.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]);
const urls = [];
for (const p of parts) {
  const xml = await (await fetch(p, { headers: UA })).text();
  urls.push(...[...xml.matchAll(/<loc>([^<]+)<\/loc>/g)].map((m) => m[1]));
}
console.log(`${parts.length} parça, ${urls.length} adres`);
for (let i = 0; i < urls.length; i += 10000) {
  const res = await fetch("https://api.indexnow.org/indexnow", {
    method: "POST",
    headers: { "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ host: "gituar.com", key: KEY, keyLocation: `${SITE}/${KEY}.txt`, urlList: urls.slice(i, i + 10000) }),
  });
  console.log(`${i}–${Math.min(i + 10000, urls.length)}: ${res.status}`);
}
