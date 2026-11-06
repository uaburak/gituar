// Her sayfa isteğinden önce şarkı verisi hazır olsun (bellekte varsa anında döner).
import { defineMiddleware } from "astro:middleware";
import { loadCatalog } from "./lib/catalog.ts";

export const onRequest = defineMiddleware(async (context, next) => {
  // www.gituar.com → gituar.com (kalıcı)
  if (context.url.hostname === "www.gituar.com") {
    return Response.redirect(`https://gituar.com${context.url.pathname}${context.url.search}`, 301);
  }
  const path = context.url.pathname;
  // Statik dosyalar ve önceden hazırlanmış sayfalar için gerekmez
  if (!/\.(js|css|png|jpg|jpeg|svg|ico|webp|woff2?|map)$/.test(path)) await loadCatalog();
  const res = await next();
  res.headers.set("X-Content-Type-Options", "nosniff");
  res.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  res.headers.set("X-Frame-Options", "SAMEORIGIN");
  res.headers.set("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
  // Sayfalar tarayıcıda kısa süre önbellekte kalsın; veri en geç birkaç dakikada tazelenir
  if (res.status === 200 && (res.headers.get("Content-Type") ?? "").includes("text/html") && !res.headers.has("Cache-Control")) {
    res.headers.set("Cache-Control", "public, max-age=60");
  }
  return res;
});
