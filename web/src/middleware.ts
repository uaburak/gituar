// Her sayfa isteğinden önce şarkı dizini hazır olsun (bellekte varsa anında döner; değişiklik kontrolü arka planda).
import { defineMiddleware } from "astro:middleware";
import { loadCatalog } from "./lib/catalog.ts";
import { sitemapPart } from "./lib/sitemap-part.ts";

export const onRequest = defineMiddleware(async (context, next) => {
  // www.gituar.com → gituar.com (kalıcı)
  if (context.url.hostname === "www.gituar.com") {
    return Response.redirect(`https://gituar.com${context.url.pathname}${context.url.search}`, 301);
  }
  const path = context.url.pathname;
  // Statik dosyalar ve önceden hazırlanmış sayfalar için gerekmez
  // Derlemede önceden hazırlanan sabit sayfalar şarkı dizini kullanmaz (derleme API'ye bağlı kalmasın)
  if (!context.isPrerendered && !/\.(js|css|png|jpg|jpeg|svg|ico|webp|woff2?|map|m4a)$/.test(path)) {
    const ctx = (context.locals as { runtime?: { ctx?: { waitUntil(p: Promise<unknown>): void } } }).runtime?.ctx;
    await loadCatalog(ctx ? (p) => ctx.waitUntil(p) : undefined);
  }
  // Site haritası parçaları /sitemap-0.xml, /sitemap-1.xml …: sayı katalogla artar (dosya başına sabit rota yok;
  // trailingSlash: "always" değişken .xml rotalarını eşleştirmediği için burada karşılanır)
  const part = /^\/sitemap-(\d+)\.xml$/.exec(path);
  if (part) return sitemapPart(Number(part[1]))(context as Parameters<ReturnType<typeof sitemapPart>>[0]);
  const res = await next();
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set("X-Frame-Options", "SAMEORIGIN");
  res.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  // Sayfalar tarayıcıda 1 dk önbellekte; sonra tarayıcı parmak iziyle (ETag) sorar, sayfa değişmediyse
  // gövde yerine 304 döner (sayfa tekrar indirilmez).
  if (context.request.method === "GET" && res.status === 200 && (res.headers.get("Content-Type") ?? "").includes("text/html") && !res.headers.has("Cache-Control")) {
    const html = await res.text();
    const tag = `W/"${fnv(html)}"`;
    const headers = new Headers(res.headers);
    headers.set("Cache-Control", "public, max-age=60");
    headers.set("ETag", tag);
    const inm = context.request.headers.get("If-None-Match");
    if (inm && inm.split(",").map((t) => t.trim()).includes(tag)) return new Response(null, { status: 304, headers });
    return new Response(html, { status: 200, headers });
  }
  return res;
});

/** Hızlı içerik özeti (FNV-1a, iki yarı) */
function fnv(text: string): string {
  let h1 = 0x811c9dc5, h2 = 0x01000193 ^ text.length;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    h1 = Math.imul(h1 ^ c, 0x01000193);
    h2 = Math.imul(h2 ^ c, 0x5bd1e995);
  }
  return (h1 >>> 0).toString(16).padStart(8, "0") + (h2 >>> 0).toString(16).padStart(8, "0");
}
