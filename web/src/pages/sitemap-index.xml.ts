// Site haritası dizini: istek anında. Şarkılar arttıkça 5.000'lik parçalara bölünür.
import type { APIRoute } from "astro";
import { sitemapEntries, SITEMAP_CHUNK } from "../lib/sitemap.ts";

export const GET: APIRoute = ({ site }) => {
  const base = (site?.href ?? "https://gituar.com/").replace(/\/$/, "");
  const parts = Math.min(4, Math.max(1, Math.ceil(sitemapEntries(base).length / SITEMAP_CHUNK))); // 20.000 adres üstünde sitemap-4.xml.ts eklenmeli
  const body = `<?xml version="1.0" encoding="UTF-8"?>\n<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">${
    Array.from({ length: parts }, (_, i) => `<sitemap><loc>${base}/sitemap-${i}.xml</loc></sitemap>`).join("")
  }</sitemapindex>`;
  return new Response(body, { headers: { "Content-Type": "application/xml; charset=utf-8", "Cache-Control": "public, max-age=300" } });
};
